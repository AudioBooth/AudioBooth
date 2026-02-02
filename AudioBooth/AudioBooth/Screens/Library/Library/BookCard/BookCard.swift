import API
import Combine
import SwiftUI

extension EnvironmentValues {
  @Entry var bookCardDisplayMode: BookCard.DisplayMode = .card
}

struct BookCard: View {
  @ObservedObject var model: Model

  var body: some View {
    NavigationLink(value: navigationDestination) {
      Content(model: model)
    }
    .buttonStyle(.plain)
    .contextMenu {
      if let model = model.contextMenu {
        BookCardContextMenu(model: model)
      }
    }
    .onAppear(perform: model.onAppear)
  }

  private var navigationDestination: NavigationDestination {
    if model.bookCount != nil {
      .series(id: model.id, name: model.title)
    } else {
      .book(id: model.id)
    }
  }
}

struct BookListCard: View {
  @ObservedObject var model: BookCard.Model
  @Environment(\.editMode) private var editMode

  private var isEditing: Bool {
    editMode?.wrappedValue.isEditing ?? false
  }

  var body: some View {
    BookCard.Content(model: model)
      .contentShape(Rectangle())
      .overlay {
        if !isEditing {
          NavigationLink(value: navigationDestination) {}
            .opacity(0)
        }
      }
      .contextMenu {
        if let model = model.contextMenu {
          BookCardContextMenu(model: model)
        }
      }
      .onAppear(perform: model.onAppear)
  }

  private var navigationDestination: NavigationDestination {
    if model.bookCount != nil {
      .series(id: model.id, name: model.title)
    } else {
      .book(id: model.id)
    }
  }
}

extension BookCard {
  struct Content: View {
    let model: BookCard.Model
    @Environment(\.bookCardDisplayMode) private var displayMode
    @Environment(\.editMode) private var editMode

    private var isEditing: Bool {
      editMode?.wrappedValue.isEditing ?? false
    }

    var body: some View {
      switch displayMode {
      case .card:
        cardLayout
      case .row:
        rowLayout
      }
    }

    private var cardLayout: some View {
      VStack(alignment: .leading, spacing: 8) {
        cover

        VStack(alignment: .leading, spacing: 4) {
          title
          details
        }
        .multilineTextAlignment(.leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }

    private var rowLayout: some View {
      HStack(spacing: 12) {
        rowCover

        VStack(alignment: .leading, spacing: 6) {
          title

          if let bookCount = model.bookCount {
            Text("^[\(bookCount) book](inflect: true)")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          if let author = model.author {
            rowMetadata(icon: "pencil", value: author)
          }

          if let details = model.details {
            Text(details)
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(1)
          } else if let narrator = model.narrator, !narrator.isEmpty {
            rowMetadata(icon: "person.wave.2.fill", value: narrator)
          }

          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let publishedYear = model.publishedYear {
          Text(publishedYear)
            .font(.caption)
            .foregroundColor(.secondary)
        }

        if !isEditing {
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }

    private var cover: some View {
      Cover(model: model.cover)
        .overlay(alignment: .bottomLeading) {
          ebookIndicator
            .padding(4)
            .padding(.bottom, 2)
        }
        .overlay(alignment: .topTrailing) {
          Group {
            if let bookCount = model.bookCount {
              badge {
                HStack(spacing: 2) {
                  Image(systemName: "book")
                  Text("\(bookCount)")
                }
              }
            } else if let sequence = model.sequence, !sequence.isEmpty {
              badge {
                Text("#\(sequence)")
              }
            }
          }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func badge(content: () -> some View) -> some View {
      content()
        .font(.caption2)
        .fontWeight(.medium)
        .foregroundStyle(Color.white)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(Color.black.opacity(0.6))
        .clipShape(.capsule)
        .padding(4)
    }

    private var rowCover: some View {
      Cover(model: model.cover, size: .small)
        .overlay(alignment: .bottomLeading) {
          ebookIndicator
            .padding(.leading, 2)
            .padding(.bottom, 6)
        }
        .overlay(alignment: .topTrailing) {
          if let sequence = model.sequence, !sequence.isEmpty {
            Text("#\(sequence)")
              .font(.caption2)
              .fontWeight(.medium)
              .foregroundStyle(Color.white)
              .padding(.vertical, 2)
              .padding(.horizontal, 4)
              .background(Color.black.opacity(0.6))
              .clipShape(.capsule)
              .padding(2)
          }
        }
        .frame(width: 60, height: 60)
    }

    private func rowMetadata(icon: String, value: String) -> some View {
      HStack(spacing: 4) {
        if model.details == nil {
          Image(systemName: icon)
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        Text(value)
          .font(.caption2)
          .foregroundColor(.primary)
      }
      .lineLimit(1)
    }

    private var title: some View {
      Text(model.title)
        .font(.caption)
        .foregroundColor(.primary)
        .fontWeight(.medium)
        .lineLimit(1)
        .allowsTightening(true)
    }

    @ViewBuilder
    private var details: some View {
      if let details = model.details ?? model.author {
        Text(details)
          .font(.caption2)
          .foregroundColor(.secondary)
          .lineLimit(1)
          .allowsTightening(true)
      }
    }

    @ViewBuilder
    private var ebookIndicator: some View {
      if model.hasEbook {
        Image(systemName: "book.fill")
          .font(.caption2)
          .foregroundStyle(Color.white)
          .padding(.vertical, 2)
          .padding(.horizontal, 4)
          .background(Color.black.opacity(0.6))
          .clipShape(.capsule)
      }
    }
  }
}

extension BookCard {
  enum DisplayMode: RawRepresentable {
    case card
    case row

    var rawValue: String {
      switch self {
      case .card: "card"
      case .row: "row"
      }
    }

    init?(rawValue: String) {
      switch rawValue {
      case "card", "grid":
        self = .card
      case "row", "list":
        self = .row
      default:
        return nil
      }
    }
  }

  struct Author {
    let id: String
    let name: String
  }

  struct Narrator {
    let name: String
  }

  struct Series {
    let id: String
    let name: String
  }

  @Observable
  class Model: ObservableObject, Identifiable {
    let id: String
    let title: String
    var details: String?
    let cover: Cover.Model
    let sequence: String?
    let author: String?
    let narrator: String?
    let publishedYear: String?
    let bookCount: Int?
    var contextMenu: BookCardContextMenu.Model?
    let hasEbook: Bool

    func onAppear() {}

    init(
      id: String = UUID().uuidString,
      title: String,
      details: String? = nil,
      cover: Cover.Model = Cover.Model(url: nil),
      sequence: String? = nil,
      author: String? = nil,
      narrator: String? = nil,
      publishedYear: String? = nil,
      bookCount: Int? = nil,
      contextMenu: BookCardContextMenu.Model? = nil,
      hasEbook: Bool = false
    ) {
      self.id = id
      self.title = title
      self.details = details
      self.cover = cover
      self.sequence = sequence
      self.author = author
      self.narrator = narrator
      self.publishedYear = publishedYear
      self.bookCount = bookCount
      self.contextMenu = contextMenu
      self.hasEbook = hasEbook
    }
  }
}

extension BookCard.Model {
  static let mock = BookCard.Model(
    title: "The Lord of the Rings",
    details: "J.R.R. Tolkien",
    cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"))
  )
}

#Preview("BookCard - Card Mode") {
  NavigationStack {
    LazyVGrid(
      columns: [
        GridItem(spacing: 12, alignment: .top),
        GridItem(spacing: 12, alignment: .top),
        GridItem(spacing: 12, alignment: .top),
      ],
      spacing: 20
    ) {
      BookCard(
        model: BookCard.Model(
          title: "The Lord of the Rings",
          details: "J.R.R. Tolkien",
          cover: Cover.Model(
            url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
            progress: 0.5
          )
        )
      )
      BookCard(
        model: BookCard.Model(
          title: "Dune",
          details: "Frank Herbert",
          cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"))
        )
      )
      BookCard(
        model: BookCard.Model(
          title: "The Foundation",
          details: "Isaac Asimov",
          cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"))
        )
      )
    }
    .padding()
  }
}

#Preview("BookCard - Row Mode") {
  NavigationStack {
    ScrollView {
      VStack(spacing: 12) {
        BookCard(
          model: BookCard.Model(
            title: "The Lord of the Rings",
            details: "J.R.R. Tolkien",
            cover: Cover.Model(
              url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
              progress: 0.5
            ),
            sequence: "1",
            author: "J.R.R. Tolkien",
            narrator: "Rob Inglis",
            publishedYear: "1954"
          )
        )
        BookCard(
          model: BookCard.Model(
            title: "Dune",
            details: "Frank Herbert",
            cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")),
            author: "Frank Herbert",
            narrator: "Scott Brick, Orlagh Cassidy, Euan Morton",
            publishedYear: "1965"
          )
        )
        BookCard(
          model: BookCard.Model(
            title: "The Foundation",
            details: "Isaac Asimov",
            cover: Cover.Model(url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")),
            author: "Isaac Asimov",
            narrator: "Scott Brick",
            publishedYear: "1951"
          )
        )
      }
    }
    .environment(\.bookCardDisplayMode, .row)
    .padding()
  }
}
