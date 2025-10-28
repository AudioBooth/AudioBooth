import NukeUI
import SwiftUI

struct CoverImage: View {
  let url: URL?

  init(url: URL?) {
    self.url = url
  }

  var body: some View {
    LazyImage(url: url) { state in
      if let image = state.image {
        image
          .resizable()
          .aspectRatio(contentMode: .fit)
      } else {
        Color.gray.opacity(0.3)
          .overlay {
            Image(systemName: "book.closed")
              .foregroundColor(.gray)
              .font(.title2)
          }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .aspectRatio(1, contentMode: .fit)
    .background {
      LazyImage(url: url) { state in
        state.image?
          .resizable()
          .aspectRatio(contentMode: .fill)
          .blur(radius: 5)
          .opacity(0.3)
      }
    }
    .id(url)
  }
}

#Preview("CoverImage") {
  CoverImage(
    url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")
  )
  .frame(width: 120, height: 120)
  .clipShape(RoundedRectangle(cornerRadius: 8))
  .shadow(radius: 2)
  .padding()
}
