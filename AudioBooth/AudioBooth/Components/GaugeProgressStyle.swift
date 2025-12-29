import SwiftUI

extension ProgressViewStyle where Self == GaugeProgressViewStyle {
  static var gauge: GaugeProgressViewStyle { .init() }
}

struct GaugeProgressViewStyle: ProgressViewStyle {
  let tint: Color
  let lineWidth: Double

  init(tint: Color = .accentColor, lineWidth: Double = 2) {
    self.tint = tint
    self.lineWidth = lineWidth
  }

  func makeBody(configuration: Configuration) -> some View {
    let fractionCompleted = configuration.fractionCompleted ?? 0

    return ZStack {
      ZStack {
        Circle()
          .stroke(tint.opacity(0.5), lineWidth: lineWidth)

        Circle()
          .trim(from: 0, to: fractionCompleted)
          .stroke(
            tint,
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
      }
    }
  }
}
