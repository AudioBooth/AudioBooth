import SwiftUI

struct NarrationWave: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var isAnimating = false

  private let bars = 7
  private let restingHeight: CGFloat = 8
  private let barWidth: CGFloat = 5
  private let spacing: CGFloat = 5
  private let maximumHeight: CGFloat = 44

  var body: some View {
    HStack(alignment: .center, spacing: spacing) {
      ForEach(0..<bars, id: \.self) { bar in
        Capsule()
          .fill(.tint)
          .frame(width: barWidth, height: height(of: bar))
          .animation(motion(for: bar), value: isAnimating)
      }
    }
    .frame(height: maximumHeight)
    .onAppear { isAnimating = true }
    .accessibilityHidden(true)
  }

  private func height(of bar: Int) -> CGFloat {
    guard isAnimating, !reduceMotion else { return restingHeight }
    return maximumHeight * peak(of: bar)
  }

  private func peak(of bar: Int) -> CGFloat {
    let peaks: [CGFloat] = [0.45, 0.85, 0.6, 1, 0.55, 0.9, 0.5]
    return peaks[bar % peaks.count]
  }

  private func motion(for bar: Int) -> Animation? {
    guard !reduceMotion else { return nil }
    return
      .easeInOut(duration: 0.5 + Double(bar % 3) * 0.12)
      .repeatForever(autoreverses: true)
      .delay(Double(bar) * 0.07)
  }
}
