import SwiftUI

struct PlaybackProgressView: View {
  @Binding var model: Model
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    VStack(spacing: 8) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.3))
            .frame(height: 4)

          RoundedRectangle(cornerRadius: 2)
            .fill(Color.orange)
            .frame(width: max(0, geometry.size.width * model.progress), height: 4)

          Circle()
            .fill(Color.orange)
            .frame(width: 16, height: 16)
            .offset(x: max(0, geometry.size.width * model.progress - 8))
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              model.isDragging = true
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

      HStack {
        Text(formatCurrentTime(model.current))
          .font(.caption)
          .foregroundColor(.white.opacity(0.7))

        Spacer()

        Group {
          if preferences.showFullBookDuration {
            Text(model.title)
              .lineLimit(1)
          } else {
            Text(formatTimeRemaining(model.totalTimeRemaining))
          }
        }
        .font(.caption)
        .foregroundColor(.white)
        .fontWeight(.medium)

        Spacer()

        Text("-\(formatCurrentTime(model.remaining))")
          .font(.caption)
          .foregroundColor(.white.opacity(0.7))
      }
      .monospacedDigit()
    }
  }

  private func formatTimeRemaining(_ duration: TimeInterval) -> String {
    Duration.seconds(duration).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " remaining"
  }

  private func formatCurrentTime(_ duration: TimeInterval) -> String {
    Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond))
  }
}

extension PlaybackProgressView {
  @Observable class Model {
    var progress: Double
    var current: TimeInterval
    var remaining: TimeInterval
    var total: TimeInterval
    var totalProgress: Double
    var totalTimeRemaining: TimeInterval
    var isDragging: Bool
    var title: String

    init(
      progress: Double,
      current: TimeInterval,
      remaining: TimeInterval,
      total: TimeInterval,
      totalProgress: Double,
      totalTimeRemaining: TimeInterval,
      isDragging: Bool = false,
      title: String
    ) {
      self.progress = progress
      self.current = current
      self.remaining = remaining
      self.total = total
      self.totalProgress = totalProgress
      self.totalTimeRemaining = totalTimeRemaining
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
