import API
import ActivityKit
import AppIntents
import Logging
import Models
import PlayerIntents
import RevenueCat
import SwiftUI
import UIKit
import WidgetKit

@main
struct AudioBoothApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  @Environment(\.scenePhase) private var scenePhase

  @StateObject private var libraries: LibrariesService = Audiobookshelf.shared.libraries
  @ObservedObject private var preferences = UserPreferences.shared

  init() {
    AppLogger.bootstrap()

    _ = CrashReporter.shared

    LegacyMigration.migrateIfNeeded()

    setupDatabaseCallbacks()

    LegacyMigration.migrateTrackPaths()

    _ = WatchConnectivityManager.shared
    _ = SessionManager.shared
    _ = UserPreferences.shared

    Purchases.logLevel = .error
    Purchases.configure(withAPIKey: "appl_AuBdFKRrOngbJsXGkkxDKGNbGRW")

    let player: PlayerManagerProtocol = PlayerManager.shared
    AppDependencyManager.shared.add(dependency: player)

    Task { @MainActor in
      await PlayerManager.shared.restoreLastPlayer()

      await Audiobookshelf.shared.authentication.checkServersHealth()

      await StorageManager.shared.cleanupUnusedDownloads()
    }

    endAllLiveActivities()
  }

  private func setupDatabaseCallbacks() {
    if let server = Audiobookshelf.shared.authentication.server {
      do {
        try ModelContextProvider.shared.switchToServer(server.id, serverURL: server.baseURL)
      } catch {
        AppLogger.general.error(
          "Failed to initialize database on app launch: \(error.localizedDescription)"
        )
      }
    }

    Audiobookshelf.shared.onServerSwitched = { serverID, serverURL in
      do {
        try ModelContextProvider.shared.switchToServer(serverID, serverURL: serverURL)
      } catch {
        AppLogger.general.error("Failed to switch database: \(error.localizedDescription)")
      }
    }
  }

  func endAllLiveActivities() {
    Task {
      for activity in Activity<SleepTimerActivityAttributes>.activities {
        await activity.end(
          ActivityContent(state: activity.content.state, staleDate: nil),
          dismissalPolicy: .immediate
        )
      }
    }
  }

  var body: some Scene {
    WindowGroup {
      Group {
        ContentView()
          .tint(preferences.accentColor)
          .preferredColorScheme(preferences.colorScheme.colorScheme)
      }
      .task {
        if libraries.current != nil {
          Task {
            try? await Audiobookshelf.shared.libraries.fetchFilterData()
          }
        }
      }
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .background:
        WidgetCenter.shared.reloadAllTimelines()
      case .active:
        guard Audiobookshelf.shared.authentication.isAuthenticated else { return }
        SessionManager.shared.syncUnsyncedSessions()
      default:
        break
      }
    }
    .onChange(of: libraries.current) { _, newValue in
      if newValue != nil {
        Task {
          try? await Audiobookshelf.shared.libraries.fetchFilterData()
        }
      }
    }
  }
}
