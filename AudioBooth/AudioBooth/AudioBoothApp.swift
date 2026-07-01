import API
import Logging
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
        .displayScaled()
        .tint(preferences.accentColor)
        .preferredColorScheme(preferences.colorScheme.colorScheme)
        .environment(\.appTheme, preferences.appTheme)
        .onChange(of: preferences.accentColor, initial: true) {
          updateWindowTintColor(preferences.accentColor)
          syncAccentColorToWidget(preferences.accentColor)
        }
        .onChange(of: preferences.colorScheme, initial: true) {
          updateWindowColorScheme(preferences.colorScheme)
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
        AudiobookIndexer.populate()
      case .active:
        guard Audiobookshelf.shared.authentication.isAuthenticated else { return }
        SessionManager.shared.syncUnsyncedSessions()
        PodcastAutoQueueManager.shared.refresh()

        if let server = Audiobookshelf.shared.authentication.server, server.status != .connected {
          Task { _ = try? await Audiobookshelf.shared.libraries.fetch() }
        }

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

  private func updateWindowColorScheme(_ mode: ColorSchemeMode) {
    let style: UIUserInterfaceStyle =
      switch mode {
      case .auto: .unspecified
      case .light: .light
      case .dark: .dark
      }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        window.overrideUserInterfaceStyle = style
        var vc: UIViewController? = window.rootViewController
        while let current = vc {
          current.overrideUserInterfaceStyle = style
          vc = current.presentedViewController
        }
      }
    }
  }
}
