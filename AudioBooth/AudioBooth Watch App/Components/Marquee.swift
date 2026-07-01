import SwiftUI

enum MarqueeLoopMode: String, CaseIterable, Identifiable {
  case playOnce
  case loop

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .playOnce: "Once"
    case .loop: "Loop"
    }
  }
}

struct Marquee<Content: View>: View {
  let content: Content
  var mode: MarqueeLoopMode = .playOnce
  var duration: Double = 6.0
  var delay: Double = 1.0

  @State private var width: CGFloat = .zero
  @State private var animate: Bool = false

  init(mode: MarqueeLoopMode = .playOnce, @ViewBuilder content: () -> Content) {
    self.mode = mode
    self.content = content()
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      content
        .fixedSize()

      marquee
    }
  }

  var marquee: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 30) {
        content
          .background(
            GeometryReader { geo in
              Color.clear
                .onAppear {
                  width = geo.size.width
                  animate = true
                }
                .onChange(of: geo.size.width) { _, newWidth in
                  width = newWidth
                }
            }
          )

        content
          .fixedSize()
      }
      .offset(x: animate ? -width - 30 : 0)
      .animation(animation, value: animate)
    }
    .scrollDisabled(true)
    .scrollClipDisabled()
  }

  private var animation: Animation {
    guard animate else { return .default }
    let base = Animation.linear(duration: duration).delay(delay)
    switch mode {
    case .playOnce: return base
    case .loop: return base.repeatForever(autoreverses: false)
    }
  }
}

#Preview {
  Marquee {
    HStack {
      Text("Dragon Hack")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundColor(.gray)

      Text("by Andrew Seiple")
        .font(.footnote)
        .foregroundColor(.gray)
    }
  }
  .padding()
}
