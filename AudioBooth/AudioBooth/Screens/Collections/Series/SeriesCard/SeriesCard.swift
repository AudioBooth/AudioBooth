import API
import SwiftUI

struct SeriesCard: View {
  @Bindable var model: Model
  @Environment(\.itemDisplayMode) private var displayMode

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

  @ViewBuilder
  var content: some View {
    switch displayMode {
    case .row:
      rowLayout
    case .card:
      cardLayout
    }
  }

  var rowLayout: some View {
    HStack(spacing: 12) {
      Cover(model: model.bookCovers.first ?? Cover.Model(url: nil), style: .plain)
        .overlay(alignment: .bottom) {
          ProgressOverlay(progress: model.progress)
            .padding(2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: 60, height: 60)

      VStack(alignment: .leading, spacing: 4) {
        Text(model.title)
          .font(.caption)
          .fontWeight(.medium)
          .lineLimit(1)
          .allowsTightening(true)

        Text("^[\(model.bookCount) book](inflect: true)")
          .font(.caption2)
          .foregroundColor(.secondary)

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  var cardLayout: some View {
    VStack(alignment: .leading, spacing: 6) {
      stackedCovers

      Text(model.title)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  var stackedCovers: some View {
    GeometryReader { geometry in
      let size = geometry.size.width
      let covers = Array(model.bookCovers.prefix(3))
      let backCount = max(covers.count - 1, 0)
      let stackPadding: CGFloat = CGFloat(backCount) * 4
      let coverSize = size - stackPadding

      ZStack(alignment: .topLeading) {
        ForEach(Array(covers.enumerated().reversed()), id: \.offset) { index, cover in
          if index == 0 {
            Cover(model: cover, style: .plain)
              .frame(width: coverSize, height: coverSize)
              .overlay(alignment: .bottom) {
                ProgressOverlay(progress: model.progress)
                  .padding(4)
              }
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .shadow(radius: 2)
              .overlay(alignment: .topTrailing) {
                bookCountBadge
              }
          } else {
            Cover(model: cover, style: .plain)
              .frame(width: coverSize, height: coverSize)
              .overlay(alignment: .bottom) {
                ProgressOverlay(progress: model.progress)
                  .padding(4)
              }
              .clipShape(RoundedRectangle(cornerRadius: 8))
              .shadow(radius: 1)
              .offset(
                x: CGFloat(index) * 4,
                y: CGFloat(index) * 4
              )
          }
        }
      }
      .frame(width: size, height: size, alignment: .topLeading)
    }
    .aspectRatio(1.0, contentMode: .fit)
  }

  @ViewBuilder
  var bookCountBadge: some View {
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
}

extension SeriesCard {
  @Observable
  class Model: Identifiable {
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

#Preview("SeriesCard - Row") {
  SeriesCard(model: .mock)
    .padding()
}

#Preview("SeriesCard - Card") {
  SeriesCard(model: .mock)
    .frame(width: 150)
    .padding()
    .environment(\.itemDisplayMode, .card)
}
