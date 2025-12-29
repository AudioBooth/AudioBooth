import API
import Combine
import CoreNFC
import PulseUI
import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
  @Environment(\.dismiss) var dismiss

  @ObservedObject var preferences = UserPreferences.shared

  @StateObject var model: Model

  var body: some View {
    NavigationStack(path: $model.navigationPath) {
      Form {
        Section("Preferences") {
          NavigationLink(value: "general") {
            HStack {
              Image(systemName: "gear")
              Text("General")
            }
          }

          NavigationLink(value: "home") {
            HStack {
              Image(systemName: "house")
              Text("Home")
            }
          }

          NavigationLink(value: "player") {
            HStack {
              Image(systemName: "play.circle")
              Text("Player")
            }
          }

          if NFCNDEFReaderSession.readingAvailable {
            NavigationLink(value: "advanced") {
              HStack {
                Image(systemName: "ellipsis.circle")
                Text("Advanced")
              }
            }
          }
        }

        TipJarView(model: model.tipJar)

        Section("Support") {
          Link(destination: URL(string: "https://github.com/AudioBooth/AudioBooth/issues")!) {
            HStack {
              Image(systemName: "questionmark.bubble")
              Text("Help & Feedback")
              Spacer()
              Image(systemName: "arrow.up.forward")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Link(destination: URL(string: "https://discord.gg/D2BgqfBVCJ")!) {
            HStack {
              Image(systemName: "bubble.left.and.bubble.right")
              Text("Join our Discord")
              Spacer()
              Image(systemName: "arrow.up.forward")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Link(destination: URL(string: "mailto:AudioBooth@proton.me")!) {
            HStack {
              Image(systemName: "envelope")
              Text("Email Support")
              Spacer()
              Image(systemName: "arrow.up.forward")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        .tint(.primary)

        debug

        Section {
          Text(model.appVersion)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 5) {
          preferences.showDebugSection.toggle()
        }
      }
      .navigationTitle("Settings")
      .navigationDestination(for: String.self) { destination in
        switch destination {
        case "playbackSession":
          if let model = model.playbackSessionList {
            PlaybackSessionListView(model: model)
          }
        case "home":
          HomePreferencesView()
        case "general":
          GeneralPreferencesView()
        case "player":
          PlayerPreferencesView()
        case "advanced":
          AdvancedPreferencesView()
        default:
          EmptyView()
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .tint(.primary)
        }
      }
    }
  }

  @ViewBuilder
  var debug: some View {
    if preferences.showDebugSection {
      Section("Debug") {
        NavigationLink(destination: ConsoleView().navigationBarBackButtonHidden(true)) {
          HStack {
            Image(systemName: "ladybug")
            Text("Console")
          }
        }

        NavigationLink(value: "playbackSession") {
          HStack {
            Image(systemName: "chart.line.uptrend.xyaxis")
            Text("Playback Sessions")
          }
        }

        Button("Clear Persistent Storage", action: model.onClearStorageTapped)
          .foregroundColor(.red)

        Text(
          "⚠️ This will delete ALL app data including downloaded content, settings, and progress. You will need to log in again. Requires app restart."
        )
        .font(.caption)
      }
    }
  }
}

extension SettingsView {
  @Observable class Model: ObservableObject {
    var navigationPath = NavigationPath()
    var tipJar: TipJarView.Model
    var playbackSessionList: PlaybackSessionListView.Model?

    var appVersion: String {
      let version =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
      let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
      return "Version \(version) (\(build))"
    }

    func onClearStorageTapped() {}
    func onExportLogsTapped() {}

    init(
      tipJar: TipJarView.Model = .mock,
      playbackSessionList: PlaybackSessionListView.Model? = nil
    ) {
      self.tipJar = tipJar
      self.playbackSessionList = playbackSessionList
    }
  }
}

extension SettingsView.Model {
  static var mock = SettingsView.Model()
}

#Preview("SettingsView") {
  SettingsView(model: .mock)
}
