import API
import Combine
import PulseUI
import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
  @Environment(\.appTheme) var theme
  @Environment(\.dismiss) var dismiss

  @ObservedObject var preferences = UserPreferences.shared

  @StateObject var model: Model

  var body: some View {
    NavigationStack(path: $model.navigationPath) {
      Form {
        Section {
          NavigationLink(value: "general") {
            PreferenceRow(
              systemImage: "sun.max",
              tint: .gray,
              title: "General",
              subtitle: "Launch, haptics, appearance"
            )
          }
          .listRowBackground(theme.colors.background.card)

          NavigationLink(value: "home") {
            PreferenceRow(
              systemImage: "house",
              tint: .green,
              title: "Home",
              subtitle: "Sections & order"
            )
          }
          .listRowBackground(theme.colors.background.card)

          NavigationLink(value: "player") {
            PreferenceRow(
              systemImage: "play.circle",
              tint: .orange,
              title: "Player",
              subtitle: "Controls, sleep, skip"
            )
          }
          .listRowBackground(theme.colors.background.card)

          NavigationLink(value: "storage") {
            PreferenceRow(
              systemImage: "cylinder",
              tint: .blue,
              title: "Storage",
              subtitle: storageSubtitle
            )
          }
          .listRowBackground(theme.colors.background.card)

          NavigationLink(value: "advanced") {
            PreferenceRow(
              systemImage: "slider.horizontal.3",
              tint: .purple,
              title: "Advanced",
              subtitle: "System integrations & extras"
            )
          }
          .listRowBackground(theme.colors.background.card)
        } header: {
          Text("Preferences")
        }

        TipJarView(model: model.tipJar)

        Section {
          externalLink(
            url: "https://github.com/AudioBooth/AudioBooth/issues",
            systemImage: "questionmark.bubble",
            tint: .blue,
            title: "Help & Feedback"
          )
          externalLink(
            url: "https://discord.gg/D2BgqfBVCJ",
            systemImage: "bubble.left.and.bubble.right",
            tint: .purple,
            title: "Join our Discord"
          )
          externalLink(
            url: "mailto:AudioBooth@proton.me",
            systemImage: "envelope",
            tint: .orange,
            title: "Email Support"
          )
        } header: {
          Text("Support")
        }

        Section {
          externalLink(
            url: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/",
            systemImage: "doc.text",
            tint: .gray,
            title: "Terms of Use"
          )
          externalLink(
            url: "https://github.com/AudioBooth/AudioBooth/blob/main/PRIVACY.md",
            systemImage: "hand.raised",
            tint: .brown,
            title: "Privacy Policy"
          )
        } header: {
          Text("Legal")
        }

        debug

        Section {
          Text(model.appVersion)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .textSelection(.enabled)
            .listRowBackground(Color.clear)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 5) {
          preferences.showDebugSection.toggle()
        }
      }
      .scrollContentBackground(.hidden)
      .background(theme.colors.background.page)
      .navigationTitle("Settings")
      .onAppear { model.storagePreferences?.onAppear() }
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
        case "storage":
          if let model = model.storagePreferences {
            StoragePreferencesView(model: model)
          }
        default:
          EmptyView()
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Label("Close", systemImage: "xmark")
          }
          .tint(.primary)
        }
      }
    }
  }

  private var storageSubtitle: String {
    guard let storage = model.storagePreferences, storage.totalBytes > 0 else {
      return String(localized: "Manage downloads & cache")
    }
    let bookCount = storage.audiobooksCount + storage.ebooksCount
    let bookText = bookCount == 1 ? String(localized: "1 book") : String(localized: "\(bookCount) books")
    return "\(storage.totalSize) · \(bookText)"
  }

  @ViewBuilder
  private func externalLink(url: String, systemImage: String, tint: Color, title: LocalizedStringKey) -> some View {
    Link(destination: URL(string: url)!) {
      HStack {
        PreferenceRow(systemImage: systemImage, tint: tint, title: title)
        Spacer()
        Image(systemName: "arrow.up.forward")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .tint(.primary)
    .listRowBackground(theme.colors.background.card)
  }

  @ViewBuilder
  var debug: some View {
    if preferences.showDebugSection {
      Section {
        NavigationLink(destination: ConsoleView().navigationBarBackButtonHidden(true)) {
          PreferenceRow(systemImage: "ladybug", tint: .blue, title: "Console")
        }
        .listRowBackground(theme.colors.background.card)

        NavigationLink(value: "playbackSession") {
          PreferenceRow(systemImage: "chart.line.uptrend.xyaxis", tint: .green, title: "Playback Sessions")
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Debug")
      }
    }
  }
}

extension SettingsView {
  @Observable class Model: ObservableObject {
    var navigationPath = NavigationPath()
    var tipJar: TipJarView.Model
    var playbackSessionList: PlaybackSessionListView.Model?
    var storagePreferences: StoragePreferencesView.Model?

    var appVersion: String = "Version \(UIApplication.appVersion)"

    func onClearStorageTapped() {}
    func onExportLogsTapped() {}

    init(
      tipJar: TipJarView.Model = .mock,
      playbackSessionList: PlaybackSessionListView.Model? = nil,
      storagePreferences: StoragePreferencesView.Model? = nil
    ) {
      self.tipJar = tipJar
      self.playbackSessionList = playbackSessionList
      self.storagePreferences = storagePreferences
    }
  }
}

extension SettingsView.Model {
  static var mock = SettingsView.Model()
}

#Preview("SettingsView") {
  SettingsView(model: .mock)
}
