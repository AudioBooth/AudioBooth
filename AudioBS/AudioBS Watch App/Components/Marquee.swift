import SwiftUI

struct Marquee<Content: View>: View {
  let content: Content
  var duration: Double = 6.0
  var delay: Double = 1.0

  @State private var width: CGFloat = .zero
  @State private var animate: Bool = false

  init(@ViewBuilder content: () -> Content) {
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
            }
          )

        content
          .fixedSize()
      }
      .offset(x: animate ? -width - 30 : 0)
      .animation(
        animate
          ? Animation.linear(duration: duration)
            .delay(delay)
            .repeatForever(autoreverses: false)
          : .default,
        value: animate
      )
    }
    .scrollDisabled(true)
    .scrollClipDisabled()
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
