import API
import Combine
import SwiftUI

struct OnboardingView: View {
  @Environment(\.appTheme) var theme

  @StateObject var model: Model

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 32) {
          header
          features
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
      }
      .background(theme.colors.background.page)
      .safeAreaInset(edge: .bottom) { actions }
      .navigationDestination(item: $model.serverModel) { serverModel in
        ServerView(model: serverModel)
      }
      .navigationDestination(item: $model.infoModel) { infoModel in
        AudiobookshelfInfoView(model: infoModel)
      }
    }
  }

  private var header: some View {
    VStack(spacing: 14) {
      Image("IconPreviews/AppIcon")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)

      Text("Welcome to AudioBooth")
        .font(.largeTitle)
        .fontWeight(.bold)
        .multilineTextAlignment(.center)

      Text("A focused player for your Audiobookshelf library.")
        .font(.title3)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var features: some View {
    VStack(alignment: .leading, spacing: 20) {
      PreferenceRow(
        systemImage: "books.vertical.fill",
        tint: .orange,
        title: "All your libraries",
        subtitle: "Books, series, collections, podcasts, and ebooks."
      )

      PreferenceRow(
        systemImage: "arrow.down.circle.fill",
        tint: .blue,
        title: "Listen offline",
        subtitle: "Download what you want and take it anywhere."
      )

      PreferenceRow(
        systemImage: "car.fill",
        tint: .green,
        title: "Wherever you listen",
        subtitle: "CarPlay, Apple Watch, widgets, and Siri."
      )

      PreferenceRow(
        systemImage: "chart.bar.fill",
        tint: .purple,
        title: "Your listening habits",
        subtitle: "Listening stats, streaks, and a daily goal."
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var actions: some View {
    VStack(spacing: 8) {
      Button(action: model.onConnectTapped) {
        Text("Connect to Server")
          .font(.headline)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)

      Button(action: model.onNoServerTapped) {
        Text("I don't have a server yet")
          .font(.subheadline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
      }
    }
    .frame(maxWidth: 520)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
    .padding(.top, 12)
    .background(theme.colors.background.page)
  }
}

extension OnboardingView {
  @Observable
  class Model: ObservableObject {
    var serverModel: ServerView.Model?
    var infoModel: AudiobookshelfInfoView.Model?

    func onConnectTapped() {}
    func onNoServerTapped() {}

    init(
      serverModel: ServerView.Model? = nil,
      infoModel: AudiobookshelfInfoView.Model? = nil
    ) {
      self.serverModel = serverModel
      self.infoModel = infoModel
    }
  }
}

#Preview {
  OnboardingView(model: OnboardingView.Model())
}
