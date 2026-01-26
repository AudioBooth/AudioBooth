import Combine
import SwiftUI

struct ItemRow: View {
  @ObservedObject var model: Model

  var body: some View {
    HStack(spacing: 12) {
      cover

      VStack(alignment: .leading, spacing: 4) {
        Text(model.title)
          .font(.headline)
          .lineLimit(2)

        if let details = model.details {
          Text(details)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .onAppear(perform: model.onAppear)
  }

  var cover: some View {
    CoverImage(url: model.coverURL)
      .overlay(alignment: .bottom) {
        ProgressOverlay(progress: model.progress)
          .padding(2)
      }
      .frame(width: 60, height: 60)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(.gray.opacity(0.3), lineWidth: 1)
      )
  }
}

extension ItemRow {
  @Observable
  class Model: ObservableObject, Identifiable {
    var id: String
    var title: String
    var details: String?
    var coverURL: URL?
    var progress: Double?

    func onAppear() {}

    init(
      id: String,
      title: String,
      details: String? = nil,
      coverURL: URL? = nil,
      progress: Double? = nil
    ) {
      self.id = id
      self.title = title
      self.details = details
      self.coverURL = coverURL
      self.progress = progress
    }
  }
}

extension ItemRow.Model {
  static var mock: ItemRow.Model {
    ItemRow.Model(
      id: "1",
      title: "The Name of the Wind",
      details: "Patrick Rothfuss",
      coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!,
      progress: 0.45
    )
  }
}

#Preview("ItemRow - No Progress") {
  List {
    NavigationLink {
      EmptyView()
    } label: {
      ItemRow(
        model: .init(
          id: "1",
          title: "Project Hail Mary",
          details: "Andy Weir",
          coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")!
        )
      )
    }
  }
}

#Preview("ItemRow - With Progress") {
  List {
    NavigationLink {
      EmptyView()
    } label: {
      ItemRow(model: .mock)
    }
  }
}

#Preview("ItemRow - No Cover") {
  List {
    NavigationLink {
      EmptyView()
    } label: {
      ItemRow(
        model: .init(
          id: "1",
          title: "The Foundation",
          details: "Isaac Asimov",
          coverURL: nil,
          progress: 0.75
        )
      )
    }
  }
}
