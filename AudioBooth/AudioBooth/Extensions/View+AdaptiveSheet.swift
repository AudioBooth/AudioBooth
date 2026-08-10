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
          #if targetEnvironment(macCatalyst)
        // Mac Catalyst has no swipe-to-dismiss gesture, and these sheets
        // have no close button of their own, so without this the only way
        // to dismiss one is the Escape key. Matches the Label("Close",
        // systemImage: "xmark") convention used everywhere else in the
        // app; top-trailing is free on every adaptive sheet except
        // EqualizerSheet, which moved its own top-trailing control to
        // make room.
        .overlay(alignment: .topTrailing) {
          Button(action: { isPresented = false }) {
            Label("Close", systemImage: "xmark")
          }
          .padding()
        }
          #endif
          .presentationDetents([.height(contentHeight)])
          .presentationDragIndicator(.visible)
      }
  }
}
