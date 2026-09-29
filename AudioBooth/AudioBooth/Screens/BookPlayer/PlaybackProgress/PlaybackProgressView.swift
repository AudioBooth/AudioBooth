import SwiftUI

struct PlaybackProgressView: View {
  @Binding var model: Model
  @ObservedObject private var preferences = UserPreferences.shared

  @State private var lastDragLocationX: CGFloat?
  @State private var scrubbingSpeed: ScrubbingSpeed = .normal
  @State private var bubbleSize: CGSize = .zero

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
          Rectangle()
            .fill(Color.white.opacity(0.3))

          Rectangle()
            .fill(Color.accentColor)
            .frame(width: max(0, geometry.size.width * model.progress))
        }
        .frame(height: 5)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay {
          if model.isDragging {
            let x = geometry.size.width * model.progress
            let inset =
              bubbleSize.width / 2 - (bubbleSize.height - TimeBubbleShape.arrowHeight) / 2
              - TimeBubbleShape.arrowWidth / 2
            let bubbleX = min(max(x, inset), geometry.size.width - inset)

            timeBubble(arrowOffset: x - bubbleX)
              .onGeometryChange(for: CGSize.self) {
                $0.size
              } action: {
                bubbleSize = $0
              }
              .position(x: bubbleX, y: -15)
              .allowsHitTesting(false)
          }
        }
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              let width = geometry.size.width
              let progress: Double

              if let lastDragLocationX {
                let speed = ScrubbingSpeed(verticalOffset: value.translation.height)
                if speed != scrubbingSpeed {
                  scrubbingSpeed = speed
                  Haptics.selection()
                }
                progress = model.progress + Double((value.location.x - lastDragLocationX) / width) * speed.rate
              } else {
                model.isDragging = true
                Haptics.selection()
                progress = Double(value.location.x / width)
              }

              lastDragLocationX = value.location.x

              let clampedProgress = min(max(0, progress), 1)
              let total = model.current + model.remaining
              model.progress = clampedProgress
              model.current = total * clampedProgress
              model.remaining = total - model.current
            }
            .onEnded { _ in
              model.onProgressChanged(model.progress)
              model.isDragging = false
              lastDragLocationX = nil
              scrubbingSpeed = .normal
            }
        )
      }
      .frame(height: 16)

      HStack {
        Text(formatCurrentTime(model.current))
          .font(.caption)
          .foregroundColor(.white.opacity(0.7))

        Group {
          if model.isDragging, let label = scrubbingSpeed.label {
            Text(label)
              .lineLimit(1)
          } else if preferences.showFullBookDuration || preferences.showBookProgressBar
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

  @ViewBuilder
  private func timeBubble(arrowOffset: CGFloat) -> some View {
    let label = Text(verbatim: formatCurrentTime(model.current))
      .font(.subheadline)
      .fontWeight(.semibold)
      .monospacedDigit()
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .padding(.bottom, TimeBubbleShape.arrowHeight)
      .fixedSize()

    if #available(iOS 26.0, *) {
      label.glassEffect(.regular, in: TimeBubbleShape(arrowOffset: arrowOffset))
    } else {
      label.background(.ultraThinMaterial, in: TimeBubbleShape(arrowOffset: arrowOffset))
    }
  }

  private func formatCurrentTime(_ duration: TimeInterval) -> String {
    Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond))
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
  private struct TimeBubbleShape: Shape {
    static let arrowHeight: CGFloat = 8
    static let arrowWidth: CGFloat = 12

    var arrowOffset: CGFloat

    func path(in rect: CGRect) -> Path {
      let bubble = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - Self.arrowHeight)
      let cornerRadius = bubble.height / 2
      let arrowInset = cornerRadius + Self.arrowWidth / 2
      let arrowX = min(max(rect.midX + arrowOffset, rect.minX + arrowInset), rect.maxX - arrowInset)

      var path = Path()
      path.move(to: CGPoint(x: bubble.minX + cornerRadius, y: bubble.minY))
      path.addLine(to: CGPoint(x: bubble.maxX - cornerRadius, y: bubble.minY))
      path.addArc(
        center: CGPoint(x: bubble.maxX - cornerRadius, y: bubble.midY),
        radius: cornerRadius,
        startAngle: .degrees(-90),
        endAngle: .degrees(90),
        clockwise: false
      )
      path.addLine(to: CGPoint(x: arrowX + Self.arrowWidth / 2, y: bubble.maxY))
      path.addLine(to: CGPoint(x: arrowX, y: rect.maxY))
      path.addLine(to: CGPoint(x: arrowX - Self.arrowWidth / 2, y: bubble.maxY))
      path.addLine(to: CGPoint(x: bubble.minX + cornerRadius, y: bubble.maxY))
      path.addArc(
        center: CGPoint(x: bubble.minX + cornerRadius, y: bubble.midY),
        radius: cornerRadius,
        startAngle: .degrees(90),
        endAngle: .degrees(270),
        clockwise: false
      )
      path.closeSubpath()
      return path
    }
  }

  private enum ScrubbingSpeed {
    case normal
    case half
    case quarter
    case fine

    init(verticalOffset: CGFloat) {
      switch verticalOffset {
      case ..<50: self = .normal
      case ..<100: self = .half
      case ..<150: self = .quarter
      default: self = .fine
      }
    }

    var rate: Double {
      switch self {
      case .normal: 1
      case .half: 0.5
      case .quarter: 0.25
      case .fine: 0.1
      }
    }

    var label: LocalizedStringResource? {
      switch self {
      case .normal: nil
      case .half: "Half-Speed Scrubbing"
      case .quarter: "Quarter-Speed Scrubbing"
      case .fine: "Fine Scrubbing"
      }
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
