import API
import AuthenticationServices
import CoreImage.CIFilterBuiltins
import Foundation
import KeychainAccess
import Logging
import Models
import SwiftUI
import UIKit

final class ServerViewModel: ServerView.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private var oidcAuthManager: OIDCAuthenticationManager?
  private var playerManager: PlayerManager { .shared }

  private var libraryData: [API.Library] = []
  private var server: Server?
  private var pendingConnectionID: String?

  private final class NewServerAuthViewModel: AuthenticationView.Model {
    weak var parent: ServerViewModel?

    init(parent: ServerViewModel) {
      self.parent = parent
      super.init()
    }

    override func onLoginTapped() {
      parent?.performNewServerLogin(
        username: username,
        password: password,
        authModel: self
      )
    }

    override func onOIDCLoginTapped() {
      parent?.performNewServerOIDCLogin(authModel: self)
    }
  }

  init(exportConnection: DeepLinkManager.ExportConnection) {
    self.server = nil

    let customHeadersVM = CustomHeadersViewModel(initialHeaders: exportConnection.headers)

    super.init(
      serverURL: exportConnection.url.absoluteString,
      customHeaders: customHeadersVM,
      selectedLibrary: nil,
      alias: "",
      authenticationModel: nil,
      reauthenticationModel: nil,
      status: nil,
      username: nil,
      canExportConnection: false,
      connectionSharingModel: nil
    )

    customHeadersVM.onHeadersChanged = { [weak self] headers in
      guard let self, let serverID = self.server?.id else { return }
      self.audiobookshelf.authentication.updateCustomHeaders(serverID, customHeaders: headers)
    }

    let newAuthModel = NewServerAuthViewModel(parent: self)
    newAuthModel.onAuthenticationSuccess = { [weak self] in
      self?.authenticationModel = nil
    }
    authenticationModel = newAuthModel
  }

  init(server: Server? = nil) {
    self.server = server

    let serverURL: String
    let customHeaders: [String: String]
    let selectedLibrary: Library?
    let alias: String
    let isActiveServer: Bool
    let username: String?
    let canExportConnection: Bool
    let connectionSharingModel: ConnectionSharingPage.Model?

    if let server {
      serverURL = server.baseURL.absoluteString
      customHeaders = server.customHeaders
      alias = server.alias ?? ""
      isActiveServer = audiobookshelf.authentication.server?.id == server.id

      if isActiveServer, let current = audiobookshelf.libraries.current {
        selectedLibrary = Library(id: current.id, name: current.name)
      } else {
        selectedLibrary = nil
      }

      switch server.token {
      case .legacy:
        username = nil
        canExportConnection = false
        connectionSharingModel = nil
      case .bearer(let accessToken, _, _):
        username = JWT(accessToken)?.username
        canExportConnection = true
        connectionSharingModel = ConnectionSharingPageViewModel(server: server)
      }
    } else {
      serverURL = ""
      customHeaders = [:]
      selectedLibrary = nil
      alias = ""
      isActiveServer = false
      username = nil
      canExportConnection = false
      connectionSharingModel = nil
    }

    let authModel: AuthenticationView.Model?
    let reauthModel: AuthenticationView.Model?

    if let server {
      authModel = nil

      let needsReauth: Bool
      if server.status == .authenticationError {
        needsReauth = true
      } else if case .bearer(_, _, let expiresAt) = server.token {
        needsReauth = Date().timeIntervalSince1970 >= expiresAt
      } else {
        needsReauth = false
      }

      if needsReauth {
        reauthModel = AuthenticationViewModel(server: server)
      } else {
        reauthModel = nil
      }
    } else {
      authModel = nil
      reauthModel = nil
    }

    super.init(
      serverURL: serverURL,
      customHeaders: CustomHeadersViewModel(initialHeaders: customHeaders),
      selectedLibrary: selectedLibrary,
      alias: alias,
      authenticationModel: authModel,
      reauthenticationModel: reauthModel,
      status: server?.status,
      username: username,
      canExportConnection: canExportConnection,
      connectionSharingModel: connectionSharingModel
    )

    if let customHeadersVM = self.customHeaders as? CustomHeadersViewModel {
      customHeadersVM.onHeadersChanged = { [weak self] headers in
        guard let self, let serverID = self.server?.id else { return }
        self.audiobookshelf.authentication.updateCustomHeaders(serverID, customHeaders: headers)
      }
    }

    if server == nil {
      let newAuthModel = NewServerAuthViewModel(parent: self)
      newAuthModel.onAuthenticationSuccess = { [weak self] in
        self?.authenticationModel = nil
      }
      authenticationModel = newAuthModel
    }

    if let reauthViewModel = reauthModel as? AuthenticationViewModel {
      reauthViewModel.onAuthenticationSuccess = { [weak self] in
        self?.reauthenticationModel = nil
        Task {
          await self?.fetchLibraries()
        }
      }
    }
  }

  override func onAppear() {
    if let server {
      let needsReauth: Bool

      if server.status == .authenticationError {
        needsReauth = true
      } else if case .bearer(_, _, let expiresAt) = server.token {
        needsReauth = Date().timeIntervalSince1970 >= expiresAt
      } else {
        needsReauth = false
      }

      if needsReauth {
        let reauthViewModel = AuthenticationViewModel(server: server)
        reauthViewModel.onAuthenticationSuccess = { [weak self] in
          self?.reauthenticationModel = nil
          Task {
            await self?.fetchLibraries()
          }
        }
        reauthenticationModel = reauthViewModel
      } else {
        reauthenticationModel = nil
      }
    } else {
      reauthenticationModel = nil
    }

    if let server, server.status == .connected {
      Task {
        await fetchLibraries()
      }
    }
  }

  private func performNewServerLogin(
    username: String,
    password: String,
    authModel: AuthenticationView.Model
  ) {
    guard !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return
    }

    authModel.isLoading = true
    let normalizedURL = buildFullServerURL()
    let headers = Dictionary(uniqueKeysWithValues: customHeaders.headers.map { ($0.key, $0.value) })

    Task {
      do {
        let connectionID = try await audiobookshelf.authentication.login(
          serverURL: normalizedURL,
          username: username.trimmingCharacters(in: .whitespacesAndNewlines),
          password: password,
          customHeaders: headers
        )
        authModel.password = ""
        pendingConnectionID = connectionID
        server = audiobookshelf.authentication.servers[connectionID]
        authenticationModel = nil
        await fetchLibraries()
      } catch {
        AppLogger.viewModel.error("Login failed: \(error.localizedDescription)")
        Toast(error: error.localizedDescription).show()
      }

      authModel.isLoading = false
    }
  }

  private func performNewServerOIDCLogin(authModel: AuthenticationView.Model) {
    guard !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    let normalizedURL = buildFullServerURL()
    let headers = Dictionary(uniqueKeysWithValues: customHeaders.headers.map { ($0.key, $0.value) })

    authModel.isLoading = true

    let authManager = OIDCAuthenticationManager(
      serverURL: normalizedURL,
      customHeaders: headers
    )
    authManager.delegate = self
    self.oidcAuthManager = authManager

    authManager.start()
  }

  func showError(_ message: String) {
    Toast(error: message).show()
  }

  override func onDiscoverServersTapped() {
    showDiscoveryPortAlert = true
  }

  func performDiscovery() {
    isDiscovering = true
    discoveredServers = []

    Task {
      let port = Int(discoveryPort) ?? 13378
      let servers = await audiobookshelf.networkDiscovery.discoverServers(port: port)
      discoveredServers = servers

      isDiscovering = false
    }
  }

  override func onServerSelected(_ server: DiscoveredServer) {
    serverURL = server.serverURL.absoluteString
    fetchServerStatusAndUpdateAuth()
  }

  override func onLibraryTapped(_ library: Library) {
    guard
      library.id != selectedLibrary?.id,
      let value = libraryData.first(where: { $0.id == library.id })
    else { return }

    let connectionID = pendingConnectionID ?? server?.id
    guard let connectionID else { return }

    if audiobookshelf.authentication.server?.id != connectionID {
      Task {
        do {
          try await audiobookshelf.switchToServer(connectionID)
          audiobookshelf.libraries.current = value
          selectedLibrary = library
          pendingConnectionID = nil
          Toast(success: "Switched to server and selected library").show()
        } catch {
          AppLogger.viewModel.error("Failed to switch server: \(error.localizedDescription)")
          Toast(error: "Failed to switch server").show()
        }
      }
    } else {
      audiobookshelf.libraries.current = value
      selectedLibrary = library
      pendingConnectionID = nil
    }
  }

  override func onAliasChanged(_ newAlias: String) {
    guard let connectionID = server?.id else { return }
    let trimmedAlias = newAlias.trimmingCharacters(in: .whitespacesAndNewlines)
    audiobookshelf.authentication.updateAlias(
      connectionID,
      alias: trimmedAlias.isEmpty ? nil : trimmedAlias
    )
  }

  override func onServerURLSubmit() {
    guard isValidServerURL() else { return }
    fetchServerStatusAndUpdateAuth()
  }

  private func fetchServerStatusAndUpdateAuth() {
    let fullURL = buildFullServerURL()
    guard let serverURL = URL(string: fullURL) else { return }

    Task {
      do {
        let status = try await audiobookshelf.networkDiscovery.fetchServerStatus(serverURL: serverURL)
        updateAuthenticationModel(with: status)
      } catch {
        AppLogger.viewModel.error("Failed to fetch server status: \(error.localizedDescription)")
      }
    }
  }

  private func updateAuthenticationModel(with status: ServerStatus) {
    guard let authModel = authenticationModel else { return }

    if let version = status.serverVersion,
      version.compare("2.22.0", options: .numeric) == .orderedAscending
    {
      warnings =
        "Some features may be limited on server version \(version). For the best experience, please update your server."
    } else {
      warnings = nil
    }

    var availableMethods: [AuthenticationView.Model.AuthenticationMethod] = []

    if status.supportsLocal {
      availableMethods.append(.usernamePassword)
    }

    if status.supportsOIDC {
      availableMethods.append(.oidc)
    }

    if availableMethods.isEmpty {
      availableMethods = [.usernamePassword, .oidc]
    }

    authModel.availableAuthMethods = availableMethods
    authModel.shouldAutoLaunchOIDC = status.shouldAutoLaunchOIDC

    if availableMethods.contains(.oidc) && !availableMethods.contains(.usernamePassword) {
      authModel.authenticationMethod = .oidc
    } else if availableMethods.contains(.oidc) {
      authModel.authenticationMethod = .oidc
    }

    if status.shouldAutoLaunchOIDC && availableMethods.contains(.oidc) {
      authModel.onOIDCLoginTapped()
    }
  }

  override func onLogoutTapped() {
    guard let serverID = server?.id else { return }

    if audiobookshelf.authentication.server?.id == serverID {
      playerManager.current = nil
    }

    audiobookshelf.logout(serverID: serverID)
    server = nil

    let newAuthModel = NewServerAuthViewModel(parent: self)
    newAuthModel.onAuthenticationSuccess = { [weak self] in
      self?.authenticationModel = nil
    }
    authenticationModel = newAuthModel

    discoveredServers = []
    libraries = []
    selectedLibrary = nil

    if let appGroupURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
    ) {
      let serverDirectory = appGroupURL.appendingPathComponent(serverID)

      if FileManager.default.fileExists(atPath: serverDirectory.path) {
        try? FileManager.default.removeItem(at: serverDirectory)
      }
    }
  }

  private func fetchLibraries() async {
    let connectionID = pendingConnectionID ?? server?.id
    guard let connectionID else { return }

    isLoadingLibraries = true

    do {
      let fetchedLibraries = try await audiobookshelf.libraries.fetch(serverID: connectionID)

      libraryData = fetchedLibraries

      self.libraries = fetchedLibraries.map({ Library(id: $0.id, name: $0.name) })
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

      if libraries.count == 1, let singleLibrary = libraries.first, selectedLibrary == nil,
        audiobookshelf.libraries.current == nil
      {
        onLibraryTapped(singleLibrary)
      }
    } catch {
      Toast(error: "Failed to load libraries").show()

      if let server, server.status == .authenticationError {
        let reauthViewModel = AuthenticationViewModel(server: server)
        reauthViewModel.onAuthenticationSuccess = { [weak self] in
          self?.reauthenticationModel = nil
          Task {
            await self?.fetchLibraries()
          }
        }
        self.reauthenticationModel = reauthViewModel
      }
    }

    isLoadingLibraries = false
  }

  private func isValidServerURL() -> Bool {
    let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedURL.isEmpty else { return false }

    let fullURL = buildFullServerURL()
    guard let url = URL(string: fullURL) else { return false }

    return url.scheme == "http" || url.scheme == "https"
  }

  private func buildFullServerURL() -> String {
    let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)

    var fullURL: String
    if trimmedURL.hasPrefix("http://") || trimmedURL.hasPrefix("https://") {
      fullURL = trimmedURL
    } else {
      fullURL = serverScheme.rawValue + trimmedURL
    }

    if useSubdirectory {
      let trimmedSubdirectory =
        subdirectory
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

      if !trimmedSubdirectory.isEmpty {
        fullURL = fullURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        fullURL += "/" + trimmedSubdirectory
      }
    }

    return fullURL
  }
}

extension ServerViewModel: OIDCAuthenticationDelegate {
  func oidcAuthenticationDidSucceed(connectionID: String) {
    pendingConnectionID = connectionID
    server = audiobookshelf.authentication.servers[connectionID]
    authenticationModel?.isLoading = false
    authenticationModel = nil
    oidcAuthManager = nil
    Toast(success: "Successfully authenticated with SSO").show()
    Task {
      await fetchLibraries()
    }
  }

  func oidcAuthentication(didFailWithError error: Error) {
    if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
      authenticationModel?.isLoading = false
      oidcAuthManager = nil
    } else {
      showError("SSO login failed: \(error.localizedDescription)")
      authenticationModel?.isLoading = false
      oidcAuthManager = nil
    }
  }
}
