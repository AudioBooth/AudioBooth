import API
import SwiftUI

struct NarratorCard: View {
  @Bindable var model: Model

  var body: some View {
    NavigationLink(value: NavigationDestination.narrator(name: model.name)) {
      content
    }
    .buttonStyle(.plain)
  }

  var content: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .topTrailing) {
        GeometryReader { geometry in
          let size = geometry.size.width

          ZStack {
            if let imageURL = model.imageURL {
              LazyImage(url: imageURL) { state in
                if let image = state.image {
                  image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                } else {
                  Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                      Image(systemName: "person.circle")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    )
                }
              }
              .frame(width: size, height: size)
              .clipShape(Circle())
            } else {
              Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)
                .overlay(
                  Image(systemName: "person.circle")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                )
            }
          }
        }
        .aspectRatio(1.0, contentMode: .fit)

        if model.bookCount > 0 {
          Text("\(model.bookCount)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor)
            .clipShape(Capsule())
            .padding(.top, 8)
        }
      }

      Text(model.name)
        .font(.footnote)
        .fontWeight(.bold)
        .lineLimit(2)
        .padding(.horizontal)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
    }
  }
}

extension NarratorCard {
  @Observable class Model {
    var id: String
    var name: String
    var bookCount: Int
    var imageURL: URL?

    init(
      id: String = UUID().uuidString,
      name: String = "",
      bookCount: Int = 0,
      imageURL: URL? = nil
    ) {
      self.id = id
      self.name = name
      self.bookCount = bookCount
      self.imageURL = imageURL
    }
  }
}

extension NarratorCard.Model {
  static var mock: NarratorCard.Model {
    return NarratorCard.Model(
      name: "Stephen Fry",
      bookCount: 25,
      imageURL: URL(
        string:
          "https://upload.wikimedia.org/wikipedia/commons/thumb/9/96/Stephen_Fry_2013.jpg/220px-Stephen_Fry_2013.jpg"
      )
    )
  }
}

#Preview("NarratorCard - Mock") {
  LazyVGrid(
    columns: [
      GridItem(spacing: 12, alignment: .top),
      GridItem(spacing: 12, alignment: .top),
      GridItem(spacing: 12, alignment: .top),
    ],
    spacing: 20
  ) {
    NarratorCard(model: .mock)
    NarratorCard(model: .mock)
    NarratorCard(model: .mock)
  }
  .padding()
}
