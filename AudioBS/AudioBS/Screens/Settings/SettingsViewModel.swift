import Audiobookshelf
import Foundation
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
    let normalizedURL = normalizeServerURL(
      serverURL.trimmingCharacters(in: .whitespacesAndNewlines))
    serverURL = normalizedURL

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
        ToastManager.shared.show(error: "Login failed: \(error.localizedDescription)")
        isAuthenticated = false
      }

      isLoading = false
    }
  }

  override func onOIDCLoginTapped() {
    guard !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    let normalizedURL = normalizeServerURL(
      serverURL.trimmingCharacters(in: .whitespacesAndNewlines))
    serverURL = normalizedURL

    isLoading = true

    let authManager = OIDCAuthenticationManager(serverURL: normalizedURL)
    authManager.delegate = self
    self.oidcAuthManager = authManager

    authManager.start()
  }

  func showError(_ message: String) {
    ToastManager.shared.show(error: message)
    isLoading = false
  }

  override func onClearStorageTapped() {
    Task {
      do {
        try RecentlyPlayedItem.deleteAll()
        PlayerManager.shared.clearCurrent()
        ToastManager.shared.show(success: "Storage cleared successfully")
      } catch {
        print("Failed to clear storage: \(error.localizedDescription)")
        ToastManager.shared.show(error: "Failed to clear storage: \(error.localizedDescription)")
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

  private func normalizeServerURL(_ url: String) -> String {
    let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmedURL.hasPrefix("http://") || trimmedURL.hasPrefix("https://") {
      return trimmedURL
    } else {
      return "http://" + trimmedURL
    }
  }

}

extension SettingsViewModel: OIDCAuthenticationDelegate {
  func oidcAuthenticationDidSucceed() {
    isAuthenticated = true
    navigationPath.append("libraries")
    isLoading = false
    oidcAuthManager = nil
    ToastManager.shared.show(success: "Successfully authenticated with SSO")
  }

  func oidcAuthentication(didFailWithError error: Error) {
    showError("SSO login failed: \(error.localizedDescription)")
    isLoading = false
    oidcAuthManager = nil
  }
}
