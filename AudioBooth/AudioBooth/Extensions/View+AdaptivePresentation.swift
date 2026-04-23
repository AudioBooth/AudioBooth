import SwiftUI

extension View {
  @ViewBuilder
  func adaptivePresentation<Content: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    modifier(
      AdaptivePresentationModifier(
        isPresented: isPresented,
        content: content
      )
    )
  }
}

struct AdaptivePresentationModifier<Presented: View>: ViewModifier {
  @Binding var isPresented: Bool

  let content: () -> Presented

  func body(content base: Content) -> some View {
    if UIDevice.current.userInterfaceIdiom != .phone {
      base.fullScreenCover(isPresented: $isPresented) {
        content()
      }
    } else {
      base.sheet(isPresented: $isPresented) {
        content()
      }
    }
  }
}
