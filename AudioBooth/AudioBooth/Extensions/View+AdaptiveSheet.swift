import SwiftUI

extension View {
  func adaptiveSheet<Content: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    modifier(AdaptiveSheetModifier(isPresented: isPresented, sheetContent: content))
  }
}

struct AdaptiveSheetModifier<SheetContent: View>: ViewModifier {
  @Binding var isPresented: Bool
  @State private var contentHeight: CGFloat = 0
  let sheetContent: () -> SheetContent

  func body(content: Content) -> some View {
    content
      .background(
        sheetContent()
          .background(
            GeometryReader { proxy in
              Color.clear
                .task(id: proxy.size.height) {
                  contentHeight = proxy.size.height
                }
            }
          )
          .hidden()
      )
      .sheet(isPresented: $isPresented) {
        sheetContent()
          .background(
            GeometryReader { proxy in
              Color.clear
                .onChange(of: proxy.size.height) {
                  withAnimation {
                    contentHeight = proxy.size.height
                  }
                }
            }
          )
          .presentationDetents([.height(contentHeight)])
          .presentationDragIndicator(.visible)
      }
  }
}
