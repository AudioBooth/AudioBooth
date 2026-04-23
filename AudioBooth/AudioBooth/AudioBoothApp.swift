import API
import Logging
import Models
import PlayerIntents
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
        .onChange(of: preferences.accentColor, initial: true) {
          updateWindowTintColor(preferences.accentColor)
          syncAccentColorToWidget(preferences.accentColor)
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

  private func syncAccentColorToWidget(_ color: Color?) {
    let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")
    sharedDefaults?.set(color?.rawValue, forKey: "accentColor")
    WidgetCenter.shared.reloadAllTimelines()
  }

  private func updateWindowTintColor(_ color: Color?) {
    let color = color.map(UIColor.init)
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        window.tintColor = color
      }
    }
  }
}
