import Combine
import SwiftUI

struct AssistedPlayer: View {
  @ObservedObject var model: BookPlayer.Model
  var isAssistiveAccess = false

  @Environment(\.dismiss) private var dismiss

  @ObservedObject private var playerManager = PlayerManager.shared
  @ObservedObject private var preferences = UserPreferences.shared

  @State private var closeProgress: CGFloat = 0

  var body: some View {
    VStack(spacing: 20) {
      HStack(alignment: .top, spacing: 16) {
        if !isAssistiveAccess {
          closeButton
        }

        VStack(alignment: .leading, spacing: 4) {
          if !isAssistiveAccess {
            Text(model.title)
              .font(.title2)
              .fontWeight(.bold)
              .lineLimit(2)
          }

          if let author = model.author {
            Text(author)
              .font(.title3)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      Cover(url: model.coverURL, style: .plain)
        .frame(maxWidth: 600, maxHeight: 600)
        .accessibilityHidden(true)

      playPauseButton

      HStack(spacing: 20) {
        skipBackwardButton
        skipForwardButton
      }
    }
    .padding(24)
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
    .buttonBorderShape(.roundedRectangle(radius: 26))
    .navigationTitle(model.title)
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    .assistiveAccessIcon(systemImage: "headphones")
  }

  private var closeButton: some View {
    Image(systemName: "xmark")
      .font(.body)
      .fontWeight(.semibold)
      .foregroundStyle(.secondary)
      .frame(width: 44, height: 44)
      .background(Circle().fill(.quaternary))
      .overlay {
        Circle()
          .trim(from: 0, to: closeProgress)
          .stroke(Color.assistedBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      .contentShape(.circle)
      .onLongPressGesture(minimumDuration: 5) {
        close()
      } onPressingChanged: { isPressing in
        withAnimation(isPressing ? .linear(duration: 4.5).delay(0.5) : .easeOut(duration: 0.2)) {
          closeProgress = isPressing ? 1 : 0
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel("Close")
      .accessibilityHint("Touch and hold to close")
      .accessibilityAction { close() }
  }

  private func close() {
    Haptics.impact(.medium)
    playerManager.hideFullPlayer()
    dismiss()
  }

  private var playPauseButton: some View {
    Button(action: {
      Haptics.impact(.medium)
      model.onTogglePlaybackTapped()
    }) {
      VStack(spacing: 12) {
        if model.isLoading {
          ProgressView()
            .controlSize(.large)
            .frame(height: 64)
        } else {
          Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 64))
        }
        Text(model.isPlaying ? "Pause" : "Play")
          .font(.largeTitle)
          .fontWeight(.bold)
      }
      .frame(maxWidth: .infinity, minHeight: 180)
      .transaction { $0.animation = nil }
    }
    .buttonStyle(AssistedButtonStyle(isProminent: true))
    .disabled(model.isLoading)
    .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
  }

  private var skipBackwardButton: some View {
    Button(action: {
      Haptics.impact(.light)
      model.onSkipBackwardTapped(seconds: preferences.skipBackwardInterval)
    }) {
      VStack(spacing: 8) {
        Image(systemName: "gobackward.\(Int(preferences.skipBackwardInterval))")
          .font(.system(size: 40))
        Text("Rewind")
          .font(.title2)
          .fontWeight(.semibold)
      }
      .frame(maxWidth: .infinity, minHeight: 110)
    }
    .buttonStyle(AssistedButtonStyle())
    .disabled(model.isLoading)
    .accessibilityLabel("Skip backward \(Int(preferences.skipBackwardInterval)) seconds")
  }

  private var skipForwardButton: some View {
    Button(action: {
      Haptics.impact(.light)
      model.onSkipForwardTapped(seconds: preferences.skipForwardInterval)
    }) {
      VStack(spacing: 8) {
        Image(systemName: "goforward.\(Int(preferences.skipForwardInterval))")
          .font(.system(size: 40))
        Text("Forward")
          .font(.title2)
          .fontWeight(.semibold)
      }
      .frame(maxWidth: .infinity, minHeight: 110)
    }
    .buttonStyle(AssistedButtonStyle())
    .disabled(model.isLoading)
    .accessibilityLabel("Skip forward \(Int(preferences.skipForwardInterval)) seconds")
  }
}

private struct AssistedButtonStyle: ButtonStyle {
  var isProminent = false

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorScheme) private var colorScheme

  func makeBody(configuration: Configuration) -> some View {
    let shape = ButtonBorderShape.buttonBorder
    let isDark = colorScheme == .dark
    let isPressed = configuration.isPressed
    let isLit = isDark || isProminent
    let face =
      isProminent ? Color.assistedBlue : isDark ? Color(red: 0.165, green: 0.165, blue: 0.173) : Color(white: 0.993)
    let rimTop: Color = isLit ? .white.opacity(0.57) : .black.opacity(0.02)
    let rimMiddle: Color = isLit ? .white.opacity(0.22) : .black.opacity(0.05)
    let rimBottom = Color.black.opacity(0.14)

    configuration.label
      .foregroundStyle(isProminent ? Color.white : Color(.label))
      .background {
        shape
          .fill(face)
          .overlay {
            shape
              .stroke(.black.opacity(isDark ? 0.1 : 0.11), lineWidth: 3)
              .blur(radius: 1.5)
              .offset(y: -1.5)
              .mask(shape)
          }
          .overlay {
            shape
              .stroke(.white.opacity(isLit ? 0.14 : 0), lineWidth: 2)
              .blur(radius: 0.75)
              .offset(y: 1)
              .mask(shape)
          }
          .overlay {
            shape.strokeBorder(
              LinearGradient(colors: [rimTop, rimMiddle, rimBottom], startPoint: .top, endPoint: .bottom),
              lineWidth: 1
            )
          }
          .shadow(color: .black.opacity(isDark ? 0.5 : 0.12), radius: isPressed ? 2 : 6, y: isPressed ? 1 : 3)
      }
      .contentShape(shape)
      .scaleEffect(isPressed ? 0.92 : 1)
      .opacity(isEnabled ? 1 : 0.5)
      .animation(.easeOut(duration: 0.08), value: isPressed)
  }
}

#Preview {
  AssistedPlayer(model: .mock)
}

private extension Color {
  static let assistedBlue = Color(red: 0, green: 0.333, blue: 0.8)
}

extension View {
  @ViewBuilder
  func assistiveAccessIcon(systemImage: String) -> some View {
    if #available(iOS 26.0, *) {
      assistiveAccessNavigationIcon(systemImage: systemImage)
    } else {
      self
    }
  }
}
