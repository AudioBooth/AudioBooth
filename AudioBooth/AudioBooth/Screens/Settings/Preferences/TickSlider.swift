import SwiftUI

struct TickSlider: View {
  @Binding var value: Double
  let ticks: [Double]

  private let trackHeight: CGFloat = 8
  private let thumbSize: CGFloat = 28

  private var currentIndex: Int {
    ticks.indices.min(by: { abs(ticks[$0] - value) < abs(ticks[$1] - value) }) ?? 0
  }

  private func setIndex(_ index: Int) {
    let clamped = min(max(index, 0), ticks.count - 1)
    value = ticks[clamped]
  }

  var body: some View {
    GeometryReader { geo in
      let usable = max(geo.size.width - thumbSize, 1)
      let thumbX = position(for: currentIndex, in: usable)

      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.gray.opacity(0.2))
          .frame(height: trackHeight)
          .padding(.horizontal, thumbSize / 2)

        Capsule()
          .fill(Color.accentColor)
          .frame(width: thumbX, height: trackHeight)
          .offset(x: thumbSize / 2)

        ForEach(0..<ticks.count, id: \.self) { i in
          Circle()
            .fill(Color.gray.opacity(0.5))
            .frame(width: 4, height: 4)
            .offset(x: position(for: i, in: usable) + thumbSize / 2 - 2)
        }

        Circle()
          .fill(Color.white)
          .frame(width: thumbSize, height: thumbSize)
          .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
          .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
          .offset(x: thumbX)
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { g in
                value = ticks[nearestIndex(for: g.location.x, in: usable)]
              }
          )
      }
      .frame(height: thumbSize)
    }
    .frame(height: thumbSize)
    .accessibilityElement()
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: setIndex(currentIndex + 1)
      case .decrement: setIndex(currentIndex - 1)
      @unknown default: break
      }
    }
  }

  private func position(for index: Int, in usable: CGFloat) -> CGFloat {
    guard ticks.count > 1 else { return 0 }
    let ratio = CGFloat(index) / CGFloat(ticks.count - 1)
    return ratio * usable
  }

  private func nearestIndex(for x: CGFloat, in usable: CGFloat) -> Int {
    let clamped = min(max(x, 0), usable)
    let ratio = clamped / usable
    let approx = Double(ratio) * Double(ticks.count - 1)
    return Int(approx.rounded())
  }
}
