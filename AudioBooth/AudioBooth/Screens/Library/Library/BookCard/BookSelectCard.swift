import Combine
import SwiftUI

struct BookSelectCard: View {
  @ObservedObject var model: BookCard.Model
  @Environment(\.itemDisplayMode) private var displayMode
  let isSelected: Bool
  let onTap: () -> Void

  var body: some View {
    BookCard.Content(model: model)
      .contentShape(.rect)
      .overlay {
        GeometryReader { proxy in
          let center = displayMode == .row ? proxy.size.height / 2 : proxy.size.width / 2

          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(displayMode == .row ? .title2 : .largeTitle)
            .symbolRenderingMode(.palette)
            .foregroundStyle(
              isSelected ? Color.white : Color.white.opacity(0.9),
              isSelected ? Color.accentColor : Color.black.opacity(0.3)
            )
            .shadow(radius: 3)
            .position(x: center, y: center)
        }
      }
      .onTapGesture(perform: onTap)
  }
}

#Preview("BookSelectCard - Card") {
  LazyVGrid(columns: [GridItem(), GridItem()], spacing: 20) {
    BookSelectCard(
      model: BookCard.Model(
        title: "The Lord of the Rings",
        details: "J.R.R. Tolkien",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"))
      ),
      isSelected: true,
      onTap: {}
    )
    BookSelectCard(
      model: BookCard.Model(
        title: "Dune",
        details: "Frank Herbert",
        cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"))
      ),
      isSelected: false,
      onTap: {}
    )
  }
  .padding()
}
