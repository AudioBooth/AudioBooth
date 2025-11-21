import Combine
import NukeUI
import SwiftUI

struct ContinueListeningRow: View {
  @ObservedObject var model: Model

  var body: some View {
    Button(action: model.onTapped) {
      HStack(spacing: 12) {
        LazyImage(url: model.coverURL) { state in
          if let image = state.image {
            image
              .resizable()
              .aspectRatio(contentMode: .fit)
          } else {
            Color.gray
          }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(width: 50, height: 50)

        VStack(alignment: .leading, spacing: 4) {
          Text(model.title)
            .font(.caption2)
            .fontWeight(.medium)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)

          if let author = model.author {
            Text(author)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          if let timeRemaining = model.timeRemaining {
            Text(timeRemaining)
              .font(.footnote)
              .foregroundStyle(.orange)
              .lineLimit(1)
          }
        }

      }
      .padding()
      .background(Color(red: 0.1, green: 0.1, blue: 0.2))
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(Color(red: 0.2, green: 0.2, blue: 0.4), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }
}

extension ContinueListeningRow {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id: String
    var title: String
    var author: String?
    var coverURL: URL?
    var timeRemaining: String?

    func onTapped() {}

    init(
      id: String,
      title: String,
      author: String? = nil,
      coverURL: URL? = nil,
      timeRemaining: String? = nil
    ) {
      self.id = id
      self.title = title
      self.author = author
      self.coverURL = coverURL
      self.timeRemaining = timeRemaining
    }
  }
}
