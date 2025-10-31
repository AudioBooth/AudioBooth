import API
import Combine
import SwiftUI

extension EnvironmentValues {
  @Entry var bookCardDisplayMode: BookCard.DisplayMode = .card
}

struct BookCard: View {
  @StateObject var model: Model
  @Environment(\.bookCardDisplayMode) private var displayMode

  var body: some View {
    NavigationLink(value: NavigationDestination.book(id: model.id)) {
      content
    }
    .buttonStyle(.plain)
    .onAppear(perform: model.onAppear)
  }

  var content: some View {
    Group {
      switch displayMode {
      case .card:
        cardLayout
      case .row:
        rowLayout
      }
    }
  }

  var cardLayout: some View {
    VStack(alignment: .leading, spacing: 8) {
      cover

      VStack(alignment: .leading, spacing: 4) {
        title
        details
      }
      .multilineTextAlignment(.leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .topTrailing) {
      if let sequence = model.sequence {
        Text("#\(sequence)")
          .font(.caption2)
          .foregroundStyle(Color.white)
          .padding(.vertical, 2)
          .padding(.horizontal, 4)
          .background(Color.black.opacity(0.6))
          .clipShape(Capsule())
          .padding(4)
      }
    }
    .contentShape(Rectangle())
  }

  var rowLayout: some View {
    HStack(spacing: 12) {
      rowCover

      VStack(alignment: .leading, spacing: 6) {
        title

        if let author = model.author {
          rowMetadata(icon: "pencil", value: author)
        }

        if let narrator = model.narrator {
          rowMetadata(icon: "person.wave.2.fill", value: narrator)
        }

        Spacer()
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if let publishedYear = model.publishedYear {
        Text(publishedYear)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  var cover: some View {
    CoverImage(url: model.coverURL)
      .overlay(alignment: .bottom) { progressBar }
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(.gray.opacity(0.3), lineWidth: 1)
      )
      .contentShape(Rectangle())
  }

  var rowCover: some View {
    CoverImage(url: model.coverURL)
      .overlay(alignment: .bottom) { progressBar }
      .frame(width: 60, height: 60)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(.gray.opacity(0.3), lineWidth: 1)
      )
  }

  func rowMetadata(icon: String, value: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .font(.caption2)
        .foregroundColor(.secondary)
      Text(value)
        .font(.caption2)
        .foregroundColor(.primary)
    }
    .lineLimit(1)
  }

  var title: some View {
    Text(model.title)
      .font(.caption)
      .foregroundColor(.primary)
      .fontWeight(.medium)
      .lineLimit(1)
      .allowsTightening(true)
  }

  @ViewBuilder
  var details: some View {
    if let details = model.details {
      Text(details)
        .font(.caption2)
        .foregroundColor(.secondary)
        .lineLimit(1)
        .allowsTightening(true)
    }
  }

  @ViewBuilder
  var progressBar: some View {
    if let progress = model.progress, progress > 0 {
      GeometryReader { geometry in
        let progressColor: Color = progress >= 1.0 ? .green : .orange

        Rectangle()
          .fill(progressColor)
          .frame(width: geometry.size.width * progress, height: 4)
      }
      .frame(height: 4)
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

  @Observable
  class Model: ObservableObject, Identifiable {
    let id: String
    let title: String
    let details: String?
    let coverURL: URL?
    let sequence: String?
    var progress: Double?
    let author: String?
    let narrator: String?
    let publishedYear: String?

    func onAppear() {}

    init(
      id: String = UUID().uuidString,
      title: String,
      details: String?,
      coverURL: URL?,
      sequence: String? = nil,
      progress: Double? = nil,
      author: String? = nil,
      narrator: String? = nil,
      publishedYear: String? = nil
    ) {
      self.id = id
      self.title = title
      self.details = details
      self.coverURL = coverURL
      self.sequence = sequence
      self.progress = progress
      self.author = author
      self.narrator = narrator
      self.publishedYear = publishedYear
    }
  }
}

extension BookCard.Model {
  static let mock = BookCard.Model(
    title: "The Lord of the Rings",
    details: "J.R.R. Tolkien",
    coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")
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
      spacing: 20,
    ) {
      BookCard(
        model: BookCard.Model(
          title: "The Lord of the Rings",
          details: "J.R.R. Tolkien",
          coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
          progress: 0.5
        )
      )
      BookCard(
        model: BookCard.Model(
          title: "Dune",
          details: "Frank Herbert",
          coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")
        )
      )
      BookCard(
        model: BookCard.Model(
          title: "The Foundation",
          details: "Isaac Asimov",
          coverURL: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")
        )
      )
    }
    .padding()
  }
}

#Preview("BookCard - Row Mode") {
  NavigationStack {
    VStack(spacing: 12) {
      BookCard(
        model: BookCard.Model(
          title: "The Lord of the Rings",
          details: "J.R.R. Tolkien",
          coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
          progress: 0.5,
          author: "J.R.R. Tolkien",
          narrator: "Rob Inglis",
          publishedYear: "1954"
        )
      )
      BookCard(
        model: BookCard.Model(
          title: "Dune",
          details: "Frank Herbert",
          coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
          author: "Frank Herbert",
          narrator: "Scott Brick, Orlagh Cassidy, Euan Morton",
          publishedYear: "1965"
        )
      )
      BookCard(
        model: BookCard.Model(
          title: "The Foundation",
          details: "Isaac Asimov",
          coverURL: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"),
          author: "Isaac Asimov",
          narrator: "Scott Brick",
          publishedYear: "1951"
        )
      )
    }
    .environment(\.bookCardDisplayMode, .row)
    .padding()
  }
}
