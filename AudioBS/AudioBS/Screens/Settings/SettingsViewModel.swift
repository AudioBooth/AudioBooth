import API
import Foundation
import Models
import OSLog
import SwiftUI
import UIKit

final class SettingsViewModel: SettingsView.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private var oidcAuthManager: OIDCAuthenticationManager?
  private var playerManager: PlayerManager { .shared }

  init() {
    let isAuthenticated = audiobookshelf.isAuthenticated
    let serverURL = audiobookshelf.serverURL?.absoluteString ?? ""
    let existingHeaders = audiobookshelf.authentication.connection?.customHeaders ?? [:]

    super.init(
      isAuthenticated: isAuthenticated,
      serverURL: serverURL,
      username: "",
      password: "",
      customHeaders: CustomHeadersViewModel(initialHeaders: existingHeaders),
      library: LibrariesViewModel(),
      tipJar: TipJarViewModel(),
      mediaProgressList: MediaProgressListViewModel()
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
    let headers = (customHeaders as? CustomHeadersViewModel)?.getHeadersDictionary() ?? [:]

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
        navigationPath.append("libraries")
      } catch {
        AppLogger.viewModel.error("Login failed: \(error.localizedDescription)")
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
    let headers = (customHeaders as? CustomHeadersViewModel)?.getHeadersDictionary() ?? [:]

    isLoading = true

    let authManager = OIDCAuthenticationManager(serverURL: normalizedURL, customHeaders: headers)
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
        try LocalBook.deleteAll()
        DownloadManager.shared.cleanupOrphanedDownloads()
        PlayerManager.shared.clearCurrent()
        Toast(success: "Storage cleared successfully").show()
      } catch {
        AppLogger.viewModel.error("Failed to clear storage: \(error.localizedDescription)")
        Toast(error: "Failed to clear storage: \(error.localizedDescription)").show()
      }
    }
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

  override func onExportLogsTapped() {
    isExportingLogs = true

    Task {
      do {
        let fileURL = try await LogExporter.exportLogs(since: 3600)
        AppLogger.viewModel.info("Logs exported successfully to: \(fileURL.path)")

        await MainActor.run {
          presentActivityViewController(for: fileURL)
        }
      } catch {
        AppLogger.viewModel.error("Failed to export logs: \(error)")
        Toast(error: "Failed to export logs: \(error.localizedDescription)").show()
      }

      isExportingLogs = false
    }
  }

  private func presentActivityViewController(for fileURL: URL) {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = windowScene.windows.first,
      var topController = window.rootViewController
    else {
      AppLogger.viewModel.error("Could not find root view controller to present share sheet")
      return
    }

    while let presentedController = topController.presentedViewController {
      topController = presentedController
    }

    let itemProvider = NSItemProvider(contentsOf: fileURL)!
    let activityVC = UIActivityViewController(
      activityItems: [itemProvider], applicationActivities: nil)

    activityVC.completionWithItemsHandler = { _, completed, _, _ in
      if completed {
        try? FileManager.default.removeItem(at: fileURL)
        AppLogger.viewModel.info("Log file shared and cleaned up")
      } else {
        try? FileManager.default.removeItem(at: fileURL)
        AppLogger.viewModel.debug("Log file share cancelled, cleaned up temp file")
      }
    }

    if let popover = activityVC.popoverPresentationController {
      popover.sourceView = topController.view
      popover.sourceRect = CGRect(
        x: topController.view.bounds.midX,
        y: topController.view.bounds.midY,
        width: 0,
        height: 0
      )
      popover.permittedArrowDirections = []
    }

    topController.present(activityVC, animated: true)
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
