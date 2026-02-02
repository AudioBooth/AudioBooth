import API
import SwiftUI

struct SeriesCard: View {
  @Bindable var model: Model

  let titleFont: Font

  init(model: Model, titleFont: Font = .headline) {
    self._model = .init(model)
    self.titleFont = titleFont
  }

  var body: some View {
    NavigationLink(value: NavigationDestination.series(id: model.id, name: model.title)) {
      content
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  var content: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .topTrailing) {
        GeometryReader { geometry in
          let availableWidth = geometry.size.width
          let coverSize: CGFloat = availableWidth / 2
          let bookCount = model.bookCovers.prefix(10).count
          let spacing: CGFloat =
            bookCount > 1 ? (availableWidth - coverSize) / CGFloat(bookCount - 1) : 0

          ZStack(alignment: bookCount == 1 ? .center : .leading) {
            if let firstCover = model.bookCovers.first {
              LazyImage(url: firstCover.url) { state in
                if let image = state.image {
                  image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 5)
                    .opacity(0.3)
                } else {
                  RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                }
              }
              .frame(width: availableWidth, height: coverSize)
              .clipped()
              .cornerRadius(8)
            }

            ForEach(Array(model.bookCovers.prefix(10).enumerated()), id: \.offset) {
              index,
              bookCover in
              Cover(model: bookCover, style: .plain)
                .frame(width: coverSize, height: coverSize)
                .shadow(radius: 2)
                .zIndex(Double(10 - index))
                .alignmentGuide(.leading) { _ in
                  bookCount == 1 ? 0 : CGFloat(-index) * spacing
                }
            }
          }
          .frame(height: coverSize)
        }
        .aspectRatio(2.0, contentMode: .fit)
        .overlay(alignment: .bottom) {
          ProgressOverlay(progress: model.progress)
            .padding(4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))

        if model.bookCount > 0 {
          HStack(spacing: 2) {
            Image(systemName: "book")
            Text("\(model.bookCount)")
          }
          .font(.caption2)
          .fontWeight(.medium)
          .foregroundStyle(Color.white)
          .padding(.vertical, 2)
          .padding(.horizontal, 4)
          .background(Color.black.opacity(0.6))
          .clipShape(.capsule)
          .padding(4)
        }
      }

      Text(model.title)
        .font(titleFont)
        .fontWeight(.medium)
        .lineLimit(1)
        .allowsTightening(true)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension SeriesCard {
  @Observable class Model {
    var id: String
    var title: String
    var bookCount: Int
    var bookCovers: [Cover.Model]
    var progress: Double?

    init(
      id: String = UUID().uuidString,
      title: String = "",
      bookCount: Int = 0,
      bookCovers: [Cover.Model] = [],
      progress: Double? = nil
    ) {
      self.id = id
      self.title = title
      self.bookCount = bookCount
      self.bookCovers = bookCovers
      self.progress = progress
    }
  }
}

extension SeriesCard.Model {
  static var mock: SeriesCard.Model {
    let mockCovers: [Cover.Model] = [
      Cover.Model(
        url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
        title: "Book 1"
      ),
      Cover.Model(
        url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
        title: "Book 2"
      ),
      Cover.Model(
        url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"),
        title: "Book 3"
      ),
    ]

    return SeriesCard.Model(
      title: "He Who Fights with Monsters",
      bookCount: 10,
      bookCovers: mockCovers
    )
  }
}

#Preview("SeriesCard - Mock") {
  SeriesCard(model: .mock)
    .padding()
}
