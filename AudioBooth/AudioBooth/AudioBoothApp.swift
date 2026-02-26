import API
import Logging
import Models
import SwiftUI
import WidgetKit

@main
struct AudioBoothApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  @Environment(\.scenePhase) private var scenePhase

  @StateObject private var libraries: LibrariesService = Audiobookshelf.shared.libraries
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some Scene {
    WindowGroup {
      ContentView()
        .tint(preferences.accentColor)
        .preferredColorScheme(preferences.colorScheme.colorScheme)
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
