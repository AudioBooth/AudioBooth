import Audiobookshelf
import Foundation
import Models
import SwiftUI

final class SettingsViewModel: SettingsView.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private var oidcAuthManager: OIDCAuthenticationManager?
  private var playerManager: PlayerManager { .shared }

  init() {
    let isAuthenticated = audiobookshelf.isAuthenticated
    let serverURL = audiobookshelf.serverURL?.absoluteString ?? ""

    super.init(
      isAuthenticated: isAuthenticated,
      serverURL: serverURL,
      username: "",
      password: "",
      library: LibrariesViewModel()
    )

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

    Task {
      do {
        try await audiobookshelf.authentication.login(
          serverURL: normalizedURL,
          username: username.trimmingCharacters(in: .whitespacesAndNewlines),
          password: password
        )
        password = ""
        isAuthenticated = true
        navigationPath.append("libraries")
      } catch {
        print("Login failed: \(error.localizedDescription)")
        Toast(error: "Login failed: \(error.localizedDescription)").show()
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

    isLoading = true

    let authManager = OIDCAuthenticationManager(serverURL: normalizedURL)
    authManager.delegate = self
    self.oidcAuthManager = authManager

    authManager.start()
  }

  func showError(_ message: String) {
    Toast(error: message).show()
    isLoading = false
  }

  override func onClearStorageTapped() {
    Task {
      do {
        try RecentlyPlayedItem.deleteAll()
        PlayerManager.shared.clearCurrent()
        Toast(success: "Storage cleared successfully").show()
      } catch {
        print("Failed to clear storage: \(error.localizedDescription)")
        Toast(error: "Failed to clear storage: \(error.localizedDescription)").show()
      }
    }
  }

  override func onDiscoverServersTapped() {
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

  override func onLogoutTapped() {
    playerManager.current = nil
    try? RecentlyPlayedItem.deleteAll()
    try? MediaProgress.deleteAll()

    audiobookshelf.logout()
    isAuthenticated = false
    username = ""
    password = ""
    discoveredServers = []
    library = LibrariesViewModel()
  }

  private func buildFullServerURL() -> String {
    let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmedURL.hasPrefix("http://") || trimmedURL.hasPrefix("https://") {
      return trimmedURL
    }

    return serverScheme.rawValue + trimmedURL
  }
}

extension SettingsViewModel: OIDCAuthenticationDelegate {
  func oidcAuthenticationDidSucceed() {
    isAuthenticated = true
    navigationPath.append("libraries")
    isLoading = false
    oidcAuthManager = nil
    Toast(success: "Successfully authenticated with SSO").show()
  }

  func oidcAuthentication(didFailWithError error: Error) {
    showError("SSO login failed: \(error.localizedDescription)")
    isLoading = false
    oidcAuthManager = nil
  }
}
