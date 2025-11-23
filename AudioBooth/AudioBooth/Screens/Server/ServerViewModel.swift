import API
import Foundation
import KeychainAccess
import Models
import OSLog
import SwiftUI
import UIKit

final class ServerViewModel: ServerView.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private var oidcAuthManager: OIDCAuthenticationManager?
  private var playerManager: PlayerManager { .shared }

  private var libraryData: [API.Library] = []

  init() {
    let isAuthenticated = audiobookshelf.isAuthenticated
    let serverURL = audiobookshelf.serverURL?.absoluteString ?? ""
    let existingHeaders = audiobookshelf.authentication.connection?.customHeaders ?? [:]

    let selectedLibrary: Library?
    if let current = audiobookshelf.libraries.current {
      selectedLibrary = Library(id: current.id, name: current.name)
    } else {
      selectedLibrary = nil
    }

    super.init(
      isAuthenticated: isAuthenticated,
      serverURL: serverURL,
      username: "",
      password: "",
      customHeaders: CustomHeadersViewModel(initialHeaders: existingHeaders),
      selectedLibrary: selectedLibrary
    )

    if isAuthenticated {
      Task {
        await fetchLibraries()
      }
    }
  }

  override func onLoginTapped() {
    guard !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return
    }

    isLoading = true
    let normalizedURL = buildFullServerURL()
    let headers = Dictionary(uniqueKeysWithValues: customHeaders.headers.map { ($0.key, $0.value) })

    Task {
      do {
        try await audiobookshelf.authentication.login(
          serverURL: normalizedURL,
          username: username.trimmingCharacters(in: .whitespacesAndNewlines),
          password: password,
          customHeaders: headers
        )
        password = ""
        isAuthenticated = true
        await fetchLibraries()
      } catch {
        AppLogger.viewModel.error("Login failed: \(error.localizedDescription, privacy: .public)")
        Toast(error: error.localizedDescription).show()
        isAuthenticated = false
      }

      isLoading = false
    }
  }

  override func onOIDCLoginTapped() {
    guard !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    let normalizedURL = buildFullServerURL()
    let headers = Dictionary(uniqueKeysWithValues: customHeaders.headers.map { ($0.key, $0.value) })

    isLoading = true

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
    isLoading = false
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
  }

  override func onLibraryTapped(_ library: Library) {
    guard
      library.id != selectedLibrary?.id,
      let value = libraryData.first(where: { $0.id == library.id })
    else { return }

    audiobookshelf.libraries.current = value
    selectedLibrary = library
  }

  override func onLogoutTapped() {
    playerManager.current = nil
    try? LocalBook.deleteAll()
    try? MediaProgress.deleteAll()
    DownloadManager.shared.cleanupOrphanedDownloads()

    audiobookshelf.logout()
    isAuthenticated = false
    username = ""
    password = ""
    discoveredServers = []
    libraries = []
    selectedLibrary = nil
  }

  private func fetchLibraries() async {
    isLoadingLibraries = true

    do {
      let fetchedLibraries = try await audiobookshelf.libraries.fetch()

      libraryData = fetchedLibraries

      self.libraries = fetchedLibraries.map({ Library(id: $0.id, name: $0.name) })
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

      if libraries.count == 1, let singleLibrary = libraries.first, selectedLibrary == nil {
        onLibraryTapped(singleLibrary)
      }
    } catch {
      Toast(error: "Failed to load libraries").show()
    }

    isLoadingLibraries = false
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
  func oidcAuthenticationDidSucceed() {
    isAuthenticated = true
    isLoading = false
    oidcAuthManager = nil
    Toast(success: "Successfully authenticated with SSO").show()
    Task {
      await fetchLibraries()
    }
  }

  func oidcAuthentication(didFailWithError error: Error) {
    showError("SSO login failed: \(error.localizedDescription)")
    isLoading = false
    oidcAuthManager = nil
  }
}
