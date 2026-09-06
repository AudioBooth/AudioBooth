import Combine
import SwiftUI

struct AudiobookshelfInfoView: View {
  @Environment(\.appTheme) var theme

  @StateObject var model: Model

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        explainer
        steps
      }
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 24)
      .padding(.vertical, 24)
    }
    .background(theme.colors.background.page)
    .safeAreaInset(edge: .bottom) { actions }
    .navigationTitle("What is Audiobookshelf?")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var explainer: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        "Audiobookshelf is free, open source software that you run yourself, on a computer, a NAS, or a Raspberry Pi."
      )
      .font(.body)

      Text(
        "It stores your audiobooks and podcasts, tracks your progress, and serves them to apps like AudioBooth. There is no AudioBooth account and no AudioBooth cloud, so your library stays on hardware you control."
      )
      .font(.body)
      .foregroundStyle(.secondary)
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(theme.colors.background.card, in: RoundedRectangle(cornerRadius: 16))
  }

  private var steps: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Getting started")
        .font(.headline)

      PreferenceRow(
        systemImage: "server.rack",
        tint: .blue,
        title: "Install the server",
        subtitle: "Set up Audiobookshelf at home or on a host you own."
      )

      PreferenceRow(
        systemImage: "books.vertical",
        tint: .orange,
        title: "Add your books",
        subtitle: "Point it at your audiobook and podcast folders."
      )

      PreferenceRow(
        systemImage: "iphone.radiowaves.left.and.right",
        tint: .green,
        title: "Come back here",
        subtitle: "Enter the server address, sign in, and pick a library."
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var actions: some View {
    VStack(spacing: 8) {
      if let learnMoreURL = model.learnMoreURL {
        Link(destination: learnMoreURL) {
          HStack(spacing: 6) {
            Text("Visit audiobookshelf.org")
            Image(systemName: "arrow.up.forward")
              .font(.caption)
              .accessibilityHidden(true)
          }
          .font(.headline)
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }

      if let discordURL = model.discordURL {
        Link(destination: discordURL) {
          HStack(spacing: 6) {
            Text("Get help on the AudioBooth Discord")
            Image(systemName: "arrow.up.forward")
              .font(.caption2)
              .accessibilityHidden(true)
          }
          .font(.subheadline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
        }
      }
    }
    .frame(maxWidth: 520)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
    .padding(.top, 12)
    .background(theme.colors.background.page)
  }
}

extension AudiobookshelfInfoView {
  @Observable
  class Model: ObservableObject, Hashable {
    let id = UUID()

    static func == (lhs: Model, rhs: Model) -> Bool {
      lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(id)
    }

    let learnMoreURL = URL(string: "https://audiobookshelf.org")
    let discordURL = URL(string: "https://discord.gg/D2BgqfBVCJ")
  }
}

#Preview {
  NavigationStack {
    AudiobookshelfInfoView(model: AudiobookshelfInfoView.Model())
  }
}
