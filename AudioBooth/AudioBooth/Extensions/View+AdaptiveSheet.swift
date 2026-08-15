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
            .overlay(alignment: .topTrailing) {
              Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                  .font(.system(size: 12, weight: .bold))
                  .foregroundStyle(.secondary)
                  .frame(width: 28, height: 28)
                  .background(Color.primary.opacity(0.12), in: .circle)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Close")
              .padding()
            }
          #endif
          .presentationDetents([.height(contentHeight)])
          .presentationDragIndicator(.visible)
      }
  }
}
