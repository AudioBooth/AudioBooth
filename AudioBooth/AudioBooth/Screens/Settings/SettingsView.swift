import API
import Combine
import CoreNFC
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
        }
      }
    }
  }

  @ViewBuilder
  var debug: some View {
    if preferences.showDebugSection {
      Section("Debug") {
        Button(action: model.onExportLogsTapped) {
          HStack {
            if model.isExportingLogs {
              ProgressView()
                .scaleEffect(0.8)
            } else {
              Image(systemName: "square.and.arrow.up")
            }
            Text(model.isExportingLogs ? "Exporting..." : "Export Logs")
          }
        }
        .disabled(model.isExportingLogs)

        #if DEBUG
          NavigationLink(value: "playbackSession") {
            HStack {
              Image(systemName: "chart.line.uptrend.xyaxis")
              Text("Playback Sessions")
            }
          }
        #endif

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
    var isExportingLogs: Bool

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
      playbackSessionList: PlaybackSessionListView.Model? = nil,
      isExportingLogs: Bool = false
    ) {
      self.tipJar = tipJar
      self.playbackSessionList = playbackSessionList
      self.isExportingLogs = isExportingLogs
    }
  }
}

extension SettingsView.Model {
  static var mock = SettingsView.Model()
}

#Preview("SettingsView") {
  SettingsView(model: .mock)
}
