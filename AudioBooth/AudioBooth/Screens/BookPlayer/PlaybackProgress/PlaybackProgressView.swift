import SwiftUI

struct PlaybackProgressView: View {
  @Binding var model: Model
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    VStack(spacing: 8) {
      if preferences.showBookProgressBar, let supplementary {
        VStack(spacing: 4) {
          GeometryReader { geometry in
            ZStack(alignment: .leading) {
              RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.white.opacity(0.2))
                .frame(height: 3)

              RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor.opacity(0.7))
                .frame(width: max(0, geometry.size.width * supplementary.progress), height: 3)
            }
          }
          .frame(height: 3)

          HStack {
            Text(formatCurrentTime(supplementary.elapsed))
              .foregroundColor(.white.opacity(0.7))

            Spacer()

            Text(verbatim: "-\(formatCurrentTime(supplementary.remaining))")
          }
          .font(.caption)
          .foregroundColor(.white.opacity(0.7))
          .monospacedDigit()
        }
      }

      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.3))
            .frame(height: 5)

          RoundedRectangle(cornerRadius: 2)
            .fill(Color.accentColor)
            .frame(width: max(0, geometry.size.width * model.progress), height: 5)

          Circle()
            .fill(Color.accentColor)
            .frame(width: 16, height: 16)
            .offset(x: max(0, geometry.size.width * model.progress - 8))
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              if !model.isDragging {
                model.isDragging = true
                Haptics.selection()
              }

              let progress = min(max(0, value.location.x / geometry.size.width), 1)
              let total = model.current + model.remaining
              model.progress = progress
              model.current = total * progress
              model.remaining = total - model.current
            }
            .onEnded { value in
              let progress = min(max(0, value.location.x / geometry.size.width), 1)
              model.onProgressChanged(Double(progress))
              model.isDragging = false
            }
        )
      }
      .frame(height: 16)
      .accessibilityRepresentation {
        Slider(
          value: seekBinding,
          in: 0...max(1.0, model.current + model.remaining),
          step: 15
        ) {
          Text("Playback position")
        }
        .accessibilityValue(Text(accessibilityPositionDescription))
      }

      HStack {
        Text(formatCurrentTime(model.current))
          .font(.caption)
          .foregroundColor(.white.opacity(0.7))

        Group {
          if preferences.showFullBookDuration || preferences.showBookProgressBar
            || model.totalProgress == model.progress
          {
            Text(model.title)
              .lineLimit(1)
          } else {
            Text(model.totalTimeRemaining.formattedTimeRemaining)
              .accessibilityLabel(model.totalTimeRemaining.accessibilityTimeRemaining)
          }
        }
        .font(.caption)
        .foregroundColor(.white)
        .fontWeight(.medium)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal)

        Text(verbatim: "-\(formatCurrentTime(model.remaining))")
          .font(.caption)
          .foregroundColor(.white.opacity(0.7))
      }
      .monospacedDigit()
    }
  }

  private func formatCurrentTime(_ duration: TimeInterval) -> String {
    Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond))
  }

  /// Drives the VoiceOver / keyboard `Slider` exposed via `accessibilityRepresentation`.
  /// Seeks on every adjustment while keeping the visible bar in sync; the total
  /// (current + remaining) stays constant during a seek, so the slider range is stable.
  private var seekBinding: Binding<Double> {
    Binding(
      get: { model.current },
      set: { newValue in
        let total = model.current + model.remaining
        guard total > 0 else { return }
        let clamped = min(max(0, newValue), total)
        model.progress = clamped / total
        model.current = clamped
        model.remaining = total - clamped
        model.onProgressChanged(model.progress)
      }
    )
  }

  private var accessibilityPositionDescription: String {
    let elapsed = Duration.seconds(model.current)
      .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    let total = Duration.seconds(model.current + model.remaining)
      .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    return String(localized: "\(elapsed) of \(total)")
  }

  private var supplementary: (progress: Double, elapsed: TimeInterval, remaining: TimeInterval)? {
    if preferences.showFullBookDuration {
      guard let chapter = model.chapter else { return nil }
      return (chapter.progress, chapter.elapsed, chapter.remaining)
    } else {
      guard model.totalProgress != model.progress else { return nil }
      return (model.totalProgress, model.total * model.totalProgress, model.totalTimeRemaining)
    }
  }
}

extension PlaybackProgressView {
  @Observable class Model {
    struct Chapter: Equatable {
      var progress: Double
      var elapsed: TimeInterval
      var remaining: TimeInterval
    }

    var progress: Double
    var current: TimeInterval
    var remaining: TimeInterval
    var total: TimeInterval
    var totalProgress: Double
    var totalTimeRemaining: TimeInterval
    var chapter: Chapter?
    var isDragging: Bool
    var title: String

    init(
      progress: Double,
      current: TimeInterval,
      remaining: TimeInterval,
      total: TimeInterval,
      totalProgress: Double,
      totalTimeRemaining: TimeInterval,
      chapter: Chapter? = nil,
      isDragging: Bool = false,
      title: String
    ) {
      self.progress = progress
      self.current = current
      self.remaining = remaining
      self.total = total
      self.totalProgress = totalProgress
      self.totalTimeRemaining = totalTimeRemaining
      self.chapter = chapter
      self.isDragging = isDragging
      self.title = title
    }

    func onProgressChanged(_ progress: Double) {}
  }
}

extension PlaybackProgressView.Model {
  static var mock: PlaybackProgressView.Model {
    PlaybackProgressView.Model(
      progress: 0.3,
      current: 600,
      remaining: 1200,
      total: 3600,
      totalProgress: 0.5,
      totalTimeRemaining: 3000,
      title: "Sample Book Title"
    )
  }
}

#Preview {
  PlaybackProgressView(model: .constant(.mock))
    .padding()
    .background(Color.black)
}
