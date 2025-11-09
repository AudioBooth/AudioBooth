import Combine
import SwiftUI

struct BookmarkRow: View {
  @ObservedObject var model: Model

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.blue.opacity(0.1))
          .frame(width: 60, height: 60)

        Image(systemName: "bookmark.fill")
          .font(.title2)
          .foregroundStyle(.blue)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(model.title)
          .font(.headline)
          .lineLimit(1)

        Text(formattedTime)
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Text(model.createdAt, style: .relative)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      Spacer(minLength: 0)
    }
  }

  private var formattedTime: String {
    let hours = model.time / 3600
    let minutes = (model.time % 3600) / 60
    let seconds = model.time % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }
}

extension BookmarkRow {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id: String
    var title: String
    let time: Int
    let createdAt: Date

    init(
      id: String = UUID().uuidString,
      title: String,
      time: Int,
      createdAt: Date = Date()
    ) {
      self.id = id
      self.title = title
      self.time = time
      self.createdAt = createdAt
    }
  }
}

#Preview("BookmarkRow - Short Time") {
  List {
    BookmarkRow(
      model: .init(
        title: "Important Scene",
        time: 125,
        createdAt: Date().addingTimeInterval(-3600)
      )
    )
  }
}

#Preview("BookmarkRow - Long Time") {
  List {
    BookmarkRow(
      model: .init(
        title: "Chapter 15 Start",
        time: 82858,
        createdAt: Date().addingTimeInterval(-86400)
      )
    )
  }
}

#Preview("BookmarkRow - Recent") {
  List {
    BookmarkRow(
      model: .init(
        title: "qwerty",
        time: 3,
        createdAt: Date()
      )
    )
  }
}
