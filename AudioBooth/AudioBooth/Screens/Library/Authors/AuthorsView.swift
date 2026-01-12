import SwiftUI

struct AuthorsView: View {
  let authors: [AuthorCard.Model]

  var body: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 100), spacing: 20)],
      spacing: 20
    ) {
      ForEach(authors, id: \.id) { author in
        AuthorCard(model: author)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
    }
  }
}

#Preview("AuthorsView - Empty") {
  AuthorsView(authors: [])
}

#Preview("AuthorsView - With Authors") {
  let sampleAuthors: [AuthorCard.Model] = [
    AuthorCard.Model(
      name: "Andrew Seipe",
      bookCount: 15,
      imageURL: URL(
        string:
          "https://upload.wikimedia.org/wikipedia/commons/thumb/2/2c/Brandon_Sanderson_sign_books_2.jpg/220px-Brandon_Sanderson_sign_books_2.jpg"
      )
    ),
    AuthorCard.Model(
      name: "Brandon Sanderson",
      bookCount: 15,
      imageURL: URL(
        string:
          "https://upload.wikimedia.org/wikipedia/commons/thumb/2/2c/Brandon_Sanderson_sign_books_2.jpg/220px-Brandon_Sanderson_sign_books_2.jpg"
      )
    ),
    AuthorCard.Model(
      name: "Terry Pratchett",
      bookCount: 8,
      imageURL: URL(
        string:
          "https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/Terry_Pratchett_cropped.jpg/220px-Terry_Pratchett_cropped.jpg"
      )
    ),
  ]

  ScrollView {
    AuthorsView(authors: sampleAuthors)
      .padding()
  }
}
