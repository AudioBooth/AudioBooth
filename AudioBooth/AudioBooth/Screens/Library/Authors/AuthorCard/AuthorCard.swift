import API
import Combine
import SwiftUI

struct AuthorCard: View {
  @ObservedObject var model: Model

  var body: some View {
    NavigationLink(value: NavigationDestination.author(id: model.id, name: model.name)) {
      content
    }
    .buttonStyle(.plain)
  }

  var content: some View {
    VStack(alignment: .leading, spacing: 8) {
      Color.clear
        .overlay {
          if let imageURL = model.imageURL {
            LazyImage(url: imageURL) { state in
              if let image = state.image {
                image
                  .resizable()
                  .aspectRatio(contentMode: .fill)
              } else {
                placeholder
              }
            }
          } else {
            placeholder
          }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
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
          }
        }

      Text(model.name)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
  }

  private var placeholder: some View {
    Circle()
      .fill(Color.gray.opacity(0.3))
      .overlay(
        Image(systemName: "person.circle")
          .font(.largeTitle)
          .foregroundColor(.gray)
      )
  }
}

extension AuthorCard {
  @Observable class Model: ObservableObject {
    var id: String
    var name: String
    var lastFirst: String
    var bookCount: Int
    var imageURL: URL?

    init(
      id: String = UUID().uuidString,
      name: String = "",
      lastFirst: String = "",
      bookCount: Int = 0,
      imageURL: URL? = nil
    ) {
      self.id = id
      self.name = name
      self.lastFirst = lastFirst
      self.bookCount = bookCount
      self.imageURL = imageURL
    }
  }
}

extension AuthorCard.Model {
  static var mock: AuthorCard.Model {
    return AuthorCard.Model(
      name: "Brandon Sanderson",
      bookCount: 15,
      imageURL: URL(
        string:
          "https://upload.wikimedia.org/wikipedia/commons/thumb/2/2c/Brandon_Sanderson_sign_books_2.jpg/220px-Brandon_Sanderson_sign_books_2.jpg"
      )
    )
  }
}

#Preview("AuthorCard - Mock") {
  LazyVGrid(
    columns: [
      GridItem(spacing: 12, alignment: .top),
      GridItem(spacing: 12, alignment: .top),
      GridItem(spacing: 12, alignment: .top),
    ],
    spacing: 20
  ) {
    AuthorCard(model: .mock)
    AuthorCard(model: .mock)
    AuthorCard(model: .mock)
  }
  .padding()
}
