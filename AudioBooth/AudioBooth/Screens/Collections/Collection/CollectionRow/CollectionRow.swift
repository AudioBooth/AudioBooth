import Combine
import NukeUI
import SwiftUI

struct CollectionRow: View {
  @ObservedObject var model: Model

  private var gridCovers: [URL] {
    switch model.covers.count {
    case 0:
      return []
    case 1:
      return [model.covers[0]]
    case 2:
      return [model.covers[0], model.covers[1], model.covers[1], model.covers[0]]
    case 3:
      return [model.covers[0], model.covers[1], model.covers[2], model.covers[0]]
    default:
      return Array(model.covers.prefix(4))
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      coverGrid
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 4) {
        Text(model.name)
          .font(.headline)
          .lineLimit(1)

        if let description = model.description {
          Text(description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        Text("^[\(model.count) book](inflect: true)")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      Spacer(minLength: 0)
    }
  }

  @ViewBuilder
  private var coverGrid: some View {
    if gridCovers.isEmpty {
      Color.gray.opacity(0.2)
        .overlay {
          Image(systemName: "music.note.list")
            .foregroundStyle(.tertiary)
            .font(.title2)
        }
    } else if gridCovers.count == 1 {
      coverImage(gridCovers[0])
    } else {
      Grid(horizontalSpacing: 1, verticalSpacing: 1) {
        GridRow {
          coverImage(gridCovers[0])
          coverImage(gridCovers[1])
        }
        GridRow {
          coverImage(gridCovers[2])
          coverImage(gridCovers[3])
        }
      }
    }
  }

  private func coverImage(_ url: URL) -> some View {
    LazyImage(url: url) { state in
      if let image = state.image {
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Color(.systemGray5)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
  }
}

extension CollectionRow {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id: String
    let name: String
    let description: String?
    let count: Int
    let covers: [URL]

    init(
      id: String = UUID().uuidString,
      name: String,
      description: String? = nil,
      count: Int,
      covers: [URL]
    ) {
      self.id = id
      self.name = name
      self.description = description
      self.count = count
      self.covers = covers
    }
  }
}

#Preview("CollectionRow - Empty") {
  List {
    CollectionRow(
      model: .init(
        name: "Empty Collection",
        description: "A collection with no books",
        count: 0,
        covers: []
      )
    )
  }
}

#Preview("CollectionRow - One Book") {
  List {
    CollectionRow(
      model: .init(
        name: "Single Book",
        description: "A collection with one book",
        count: 1,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!
        ]
      )
    )
  }
}

#Preview("CollectionRow - Two Books") {
  List {
    CollectionRow(
      model: .init(
        name: "Two Books",
        description: "A collection with two books",
        count: 2,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")!,
        ]
      )
    )
  }
}

#Preview("CollectionRow - Three Books") {
  List {
    CollectionRow(
      model: .init(
        name: "Three Books",
        description: "A collection with three books",
        count: 3,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")!,
        ]
      )
    )
  }
}

#Preview("CollectionRow - Four+ Books") {
  List {
    CollectionRow(
      model: .init(
        name: "Science Fiction Collection",
        description: "My favorite sci-fi audiobooks",
        count: 12,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!,
        ]
      )
    )
  }
}

#Preview("CollectionRow - No Description") {
  List {
    CollectionRow(
      model: .init(
        name: "Currently Reading",
        description: nil,
        count: 5,
        covers: [
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")!,
          URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!,
        ]
      )
    )
  }
}
