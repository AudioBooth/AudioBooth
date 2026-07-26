import SwiftUI

struct PaginationFooter: View {
  let hasError: Bool
  let onLoadMore: () -> Void

  var body: some View {
    if hasError {
      Button(action: onLoadMore) {
        Label("Couldn't load more. Tap to retry.", systemImage: "arrow.clockwise")
          .font(.subheadline)
      }
      .frame(maxWidth: .infinity)
      .padding()
    } else {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding()
        .onAppear(perform: onLoadMore)
    }
  }
}

#Preview("Loading") {
  PaginationFooter(hasError: false, onLoadMore: {})
}

#Preview("Error") {
  PaginationFooter(hasError: true, onLoadMore: {})
}
