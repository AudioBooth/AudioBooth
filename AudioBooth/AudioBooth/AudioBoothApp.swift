import API
import AppIntents
import Models
import OSLog
import PlayerIntents
import RevenueCat
import SwiftUI
import UIKit
import WidgetKit

@main
struct AudioBoothApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  init() {
    Audiobookshelf.shared.authentication.migrateLegacyConnection()

    LegacyMigration.migrateIfNeeded()

    setupDatabaseCallbacks()

    LegacyMigration.migrateTrackPaths()

    _ = WatchConnectivityManager.shared
    _ = SessionManager.shared
    _ = UserPreferences.shared

    observeAuthentication()
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
    }
  }

  private func setupDatabaseCallbacks() {
    if let serverID = Audiobookshelf.shared.authentication.activeServerID,
      let connection = Audiobookshelf.shared.authentication.connection
    {
      do {
        try ModelContextProvider.shared.switchToServer(serverID, serverURL: connection.serverURL)
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

  private func observeAuthentication() {
    Audiobookshelf.shared.authentication.onAuthenticationChanged = { credentials in
      if let (serverID, serverURL, token) = credentials {
        do {
          try ModelContextProvider.shared.switchToServer(serverID, serverURL: serverURL)
        } catch {
          AppLogger.general.error(
            "Failed to switch database on login: \(error.localizedDescription)")
        }
        WatchConnectivityManager.shared.syncAuthCredentials(serverURL: serverURL, token: token)
      } else {
        WatchConnectivityManager.shared.clearAuthCredentials()
      }
    }

    if let connection = Audiobookshelf.shared.authentication.connection {
      WatchConnectivityManager.shared.syncAuthCredentials(
        serverURL: connection.serverURL, token: connection.token)
    }
  }

  private func observeLibrary() {
    Audiobookshelf.shared.libraries.onLibraryChanged = { library in
      if let library {
        WatchConnectivityManager.shared.syncLibrary(library)
        Task {
          try? await Audiobookshelf.shared.libraries.fetchFilterData()
        }
      } else {
        WatchConnectivityManager.shared.clearLibrary()
      }
    }

    if let library = Audiobookshelf.shared.libraries.current {
      WatchConnectivityManager.shared.syncLibrary(library)
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
