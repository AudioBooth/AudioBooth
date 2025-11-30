import API
import Foundation
import KeychainAccess
import Models
import OSLog
import SwiftUI
import UIKit

final class SettingsViewModel: SettingsView.Model {
  private let audiobookshelf = Audiobookshelf.shared

  init() {
    super.init(
      tipJar: TipJarViewModel(),
      playbackSessionList: PlaybackSessionListViewModel()
    )
  }

  override func onClearStorageTapped() {
    Task {
      try? LocalBook.deleteAll()
      try? MediaProgress.deleteAll()
      DownloadManager.shared.deleteAllServerData()
      PlayerManager.shared.clearCurrent()

      let keychain = Keychain(service: "me.jgrenier.AudioBS")
      try? keychain.removeAll()

      audiobookshelf.logoutAll()

      Toast(success: "All app data cleared successfully").show()
    }
  }

  override func onExportLogsTapped() {
    isExportingLogs = true

    Task {
      do {
        let fileURL = try await LogExporter.exportLogs(since: 3600)
        AppLogger.viewModel.info("Logs exported successfully to: \(fileURL.path, privacy: .public)")

        await MainActor.run {
          presentActivityViewController(for: fileURL)
        }
      } catch {
        AppLogger.viewModel.error("Failed to export logs: \(error, privacy: .public)")
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
}
