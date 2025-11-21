import API
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

  init() {
    AppLogger.bootstrap()

    LegacyMigration.migrateIfNeeded()

    setupDatabaseCallbacks()

    LegacyMigration.migrateTrackPaths()

    _ = WatchConnectivityManager.shared
    _ = SessionManager.shared
    _ = UserPreferences.shared

    observeLibrary()

    Purchases.logLevel = .error
    Purchases.configure(withAPIKey: "appl_AuBdFKRrOngbJsXGkkxDKGNbGRW")

    let player: PlayerManagerProtocol = PlayerManager.shared
    AppDependencyManager.shared.add(dependency: player)

    Task { @MainActor in
      await PlayerManager.shared.restoreLastPlayer()
    }

    Task {
      if Audiobookshelf.shared.authentication.isAuthenticated {
        await SessionManager.shared.syncUnsyncedSessions()
      }
      await Audiobookshelf.shared.authentication.checkServersHealth()
    }
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

  private func observeLibrary() {
    Audiobookshelf.shared.libraries.onLibraryChanged = { library in
      if library != nil {
        Task {
          try? await Audiobookshelf.shared.libraries.fetchFilterData()
        }
      }
    }

    if Audiobookshelf.shared.libraries.current != nil {
      Task {
        try? await Audiobookshelf.shared.libraries.fetchFilterData()
      }
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
