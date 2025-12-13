import API
import Combine
import SwiftUI

struct ContinueListeningCard: View {
  @ObservedObject var model: Model

  var body: some View {
    NavigationLink(value: NavigationDestination.book(id: model.id)) {
      VStack(alignment: .leading, spacing: 8) {
        cover

        VStack(alignment: .leading, spacing: 4) {
          title
          author
        }

        timeRemaining
          .font(.caption)
      }
      .frame(width: 220)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu { contextMenu }
    .onAppear(perform: model.onAppear)
  }

  var cover: some View {
    CoverImage(url: model.coverURL)
      .aspectRatio(1, contentMode: .fit)
      .overlay(alignment: .bottom) {
        progressBar
      }
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(.gray.opacity(0.3), lineWidth: 1)
      )
  }

  var title: some View {
    Text(model.title)
      .font(.callout)
      .fontWeight(.medium)
      .lineLimit(1)
      .foregroundColor(.primary)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  var author: some View {
    if let author = model.author {
      Text(author)
        .font(.footnote)
        .foregroundColor(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  var timeRemaining: some View {
    if let timeRemaining = model.timeRemaining {
      HStack(alignment: .top) {
        Text("Time remaining:")
          .foregroundColor(.secondary)

        Spacer()

        Text(timeRemaining)
          .foregroundColor(.primary)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }

  @ViewBuilder
  var contextMenu: some View {
    Button {
      model.onRemoveFromListTapped()
    } label: {
      Label("Remove from continue listening", systemImage: "eye.slash")
    }
  }

  @ViewBuilder
  var progressBar: some View {
    if model.progress > 0 {
      GeometryReader { geometry in
        let progressColor: Color = model.progress >= 1.0 ? .green : .orange

        Rectangle()
          .fill(progressColor)
          .frame(width: geometry.size.width * model.progress, height: 8)
      }
      .frame(height: 8)
    }
  }

}

extension ContinueListeningCard {
  @Observable
  class Model: Identifiable, ObservableObject {
    let id: String
    let title: String
    let author: String?
    let coverURL: URL?
    var progress: Double
    var timeRemaining: String?

    func onAppear() {}
    func onRemoveFromListTapped() {}

    init(
      id: String = UUID().uuidString,
      title: String,
      author: String?,
      coverURL: URL?,
      progress: Double,
      timeRemaining: String? = nil
    ) {
      self.id = id
      self.title = title
      self.author = author
      self.coverURL = coverURL
      self.progress = progress
      self.timeRemaining = timeRemaining
    }
  }
}

extension ContinueListeningCard.Model {
  static let mock = ContinueListeningCard.Model(
    title: "The Lord of the Rings",
    author: "J.R.R. Tolkien",
    coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
    progress: 0.45,
    timeRemaining: "8hr 32min left"
  )
}

#Preview("ContinueListeningCard") {
  NavigationStack {
    ScrollView(.horizontal) {
      LazyHStack(alignment: .top, spacing: 16) {
        ContinueListeningCard(model: .mock)
        ContinueListeningCard(
          model: ContinueListeningCard.Model(
            title: "Dune",
            author: "Frank Herbert",
            coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
            progress: 0.75,
            timeRemaining: "2hr 15min left"
          )
        )
      }
      .padding(.horizontal)
    }
  }
}
