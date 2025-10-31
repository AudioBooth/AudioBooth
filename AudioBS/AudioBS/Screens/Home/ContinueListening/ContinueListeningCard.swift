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

        VStack(alignment: .leading, spacing: 4) {
          if let progress = model.progress {
            HStack(alignment: .top) {
              Text("Progress:")
                .font(.caption)
                .foregroundColor(.secondary)

              Spacer()

              Text(progress.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption)
                .foregroundColor(.primary)
            }
          }

          if let timeRemaining = model.timeRemaining {
            HStack(alignment: .top) {
              Text("Time remaining:")
                .font(.caption)
                .foregroundColor(.secondary)

              Spacer()

              Text(timeRemaining)
                .font(.caption)
                .foregroundColor(.primary)
            }
          }

          lastPlayedInfo
        }
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
      .font(.headline)
      .lineLimit(2)
      .foregroundColor(.primary)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  var author: some View {
    if let author = model.author {
      Text(author)
        .font(.subheadline)
        .foregroundColor(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  var lastPlayedInfo: some View {
    if let lastPlayedAt = model.lastPlayedAt {
      HStack(alignment: .top) {
        Text("Last played:")
          .font(.caption)
          .foregroundColor(.secondary)

        Spacer()

        if lastPlayedAt == .distantFuture {
          Text("Playing now")
            .font(.caption)
            .foregroundColor(.blue)
        } else {
          Text(lastPlayedAt, style: .relative)
            .font(.caption)
            .foregroundColor(.primary)
            .monospacedDigit()
        }
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
    if let progress = model.progress, progress > 0 {
      GeometryReader { geometry in
        let progressColor: Color = progress >= 1.0 ? .green : .orange

        Rectangle()
          .fill(progressColor)
          .frame(width: geometry.size.width * progress, height: 8)
      }
      .frame(height: 8)
    }
  }

}

extension ContinueListeningCard {
  @Observable
  class Model: Comparable, Identifiable, ObservableObject {
    let id: String
    let title: String
    let author: String?
    let coverURL: URL?
    var progress: Double?
    var lastPlayedAt: Date?
    var timeRemaining: String?

    func onAppear() {}
    func onRemoveFromListTapped() {}

    init(
      id: String = UUID().uuidString,
      title: String,
      author: String?,
      coverURL: URL?,
      progress: Double?,
      lastPlayedAt: Date?,
      timeRemaining: String? = nil
    ) {
      self.id = id
      self.title = title
      self.author = author
      self.coverURL = coverURL
      self.progress = progress
      self.lastPlayedAt = lastPlayedAt
      self.timeRemaining = timeRemaining
    }

    static func == (lhs: ContinueListeningCard.Model, rhs: ContinueListeningCard.Model) -> Bool {
      lhs.id == rhs.id
    }

    static func < (lhs: ContinueListeningCard.Model, rhs: ContinueListeningCard.Model) -> Bool {
      switch (lhs.lastPlayedAt, rhs.lastPlayedAt) {
      case (.none, .none): false
      case (.some, .none): false
      case (.none, .some): true
      case let (.some(lhs), .some(rhs)): lhs < rhs
      }
    }
  }
}

extension ContinueListeningCard.Model {
  static let mock = ContinueListeningCard.Model(
    title: "The Lord of the Rings",
    author: "J.R.R. Tolkien",
    coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
    progress: 0.45,
    lastPlayedAt: Date().addingTimeInterval(-3600),
    timeRemaining: "8hr 32min remaining"
  )
}

#Preview("ContinueListeningCard") {
  NavigationStack {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 16) {
        ContinueListeningCard(model: .mock)
        ContinueListeningCard(
          model: ContinueListeningCard.Model(
            title: "Dune",
            author: "Frank Herbert",
            coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
            progress: 0.75,
            lastPlayedAt: Date().addingTimeInterval(-7200),
            timeRemaining: "2hr 15min remaining"
          ))
      }
      .padding(.horizontal)
    }
  }
}
