import API
import Combine
import NukeUI
import SwiftUI

struct AuthorDetailsView: View {
  @ObservedObject var model: Model
  @ObservedObject var preferences = UserPreferences.shared
  @State private var isDescriptionExpanded: Bool = false

  var body: some View {
    Group {
      if model.isLoading {
        ProgressView("Loading author details...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.background)
      } else if let error = model.error {
        ContentUnavailableView {
          Label("Unable to Load Author", systemImage: "exclamationmark.triangle")
        } description: {
          Text(error)
        } actions: {
          Button("Try Again") {
            model.onAppear()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
      } else {
        ScrollView {
          VStack(spacing: 24) {
            header
              .padding(.horizontal)

            if let description = model.description {
              descriptionSection(description)
                .padding(.horizontal)
            }

            if !model.allBooks.isEmpty {
              allBooksSection
            }

            ForEach(model.series, id: \.id) { seriesWithBooks in
              seriesSection(seriesWithBooks)
            }
          }
          .padding(.bottom)
        }
      }
    }
    .navigationTitle(model.name)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: model.onAppear)
  }

  private var header: some View {
    VStack(spacing: 16) {
      if let imageURL = model.imageURL {
        LazyImage(url: imageURL) { state in
          if let image = state.image {
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          } else {
            Color(.systemGray5)
          }
        }
        .frame(width: 200, height: 200)
        .clipShape(Circle())
      } else {
        Circle()
          .fill(Color.secondary.opacity(0.2))
          .frame(width: 200, height: 200)
          .overlay(
            Image(systemName: "person.fill")
              .font(.system(size: 80))
              .foregroundColor(.secondary)
          )
      }

      VStack(spacing: 8) {
        Text(model.name)
          .font(.title)
          .fontWeight(.bold)
          .multilineTextAlignment(.center)

        if let bookCount = model.bookCount {
          Text("^[\(bookCount) book](inflect: true)")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func descriptionSection(_ description: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("About")
        .font(.headline)

      Text(description)
        .font(.subheadline)
        .lineLimit(isDescriptionExpanded ? nil : 3)

      Button(action: {
        withAnimation(.easeInOut(duration: 0.25)) {
          isDescriptionExpanded.toggle()
        }
      }) {
        Text(isDescriptionExpanded ? "Show Less" : "Show More")
          .font(.subheadline)
          .foregroundColor(.accentColor)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func seriesSection(_ seriesWithBooks: Model.SeriesWithBooks) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      NavigationLink(
        value: NavigationDestination.series(
          id: seriesWithBooks.id,
          name: seriesWithBooks.name,
          libraryID: model.libraryID
        )
      ) {
        HStack {
          Text(seriesWithBooks.name)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .accessibilityAddTraits(.isHeader)

          Spacer()

          Image(systemName: "chevron.right")
            .font(.body)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(model.libraryID == nil)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 16) {
          ForEach(seriesWithBooks.books) { book in
            BookCard(model: book)
              .frame(width: 120)
          }
        }
        .padding(.horizontal)
      }
    }
  }

  private var allBooksSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      NavigationLink(
        value: NavigationDestination.authorLibrary(id: model.authorID, name: model.name, libraryID: model.libraryID)
      ) {
        HStack {
          Text("^[\(model.allBooks.count) Book](inflect: true)")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .accessibilityAddTraits(.isHeader)

          Spacer()

          Image(systemName: "chevron.right")
            .font(.body)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(model.libraryID == nil)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 16) {
          ForEach(model.allBooks) { book in
            BookCard(model: book)
              .frame(width: 120)
          }
        }
        .padding(.horizontal)
      }
    }
  }
}

extension AuthorDetailsView {
  @Observable
  class Model: ObservableObject {
    let authorID: String
    var libraryID: String?
    var name: String
    var description: String?
    var imageURL: URL?
    var bookCount: Int?
    var series: [SeriesWithBooks]
    var allBooks: [BookCard.Model]
    var isLoading: Bool
    var error: String?

    func onAppear() {}

    init(
      authorID: String,
      libraryID: String? = nil,
      name: String = "",
      description: String? = nil,
      imageURL: URL? = nil,
      bookCount: Int? = nil,
      series: [SeriesWithBooks] = [],
      allBooks: [BookCard.Model] = [],
      isLoading: Bool = true,
      error: String? = nil
    ) {
      self.authorID = authorID
      self.libraryID = libraryID
      self.name = name
      self.description = description
      self.imageURL = imageURL
      self.bookCount = bookCount
      self.series = series
      self.allBooks = allBooks
      self.isLoading = isLoading
      self.error = error
    }
  }
}

extension AuthorDetailsView.Model {
  struct SeriesWithBooks: Identifiable {
    let id: String
    let name: String
    let books: [BookCard.Model]
  }
}

extension AuthorDetailsView.Model {
  static var mock: AuthorDetailsView.Model {
    AuthorDetailsView.Model(
      authorID: "mock-author-id",
      name: "Virgil Knightley",
      description:
        "Virgil Knightley is an author of pulp fantasy largely aimed at a discerning male audience, though all are welcome to enjoy.",
      imageURL: nil,
      bookCount: 11,
      series: [
        SeriesWithBooks(
          id: "series-1",
          name: "Master Class",
          books: [
            BookCard.Model(
              id: "book-1",
              title: "Master Class",
              details: "Annabelle Hawthorne, Virgil Knightley",
              cover: Cover.Model(url: nil),
              sequence: "1"
            ),
            BookCard.Model(
              id: "book-2",
              title: "Master Class 2",
              details: "Annabelle Hawthorne, Virgil Knightley",
              cover: Cover.Model(url: nil),
              sequence: "2"
            ),
          ]
        ),
        SeriesWithBooks(
          id: "series-2",
          name: "Coven King",
          books: [
            BookCard.Model(
              id: "book-3",
              title: "Coven King 1",
              details: "Virgil Knightley, Edgar Riggs",
              cover: Cover.Model(url: nil),
              sequence: "1"
            )
          ]
        ),
      ],
      allBooks: [
        BookCard.Model(
          id: "book-4",
          title: "Standalone Book",
          details: "Virgil Knightley",
          cover: Cover.Model(url: nil)
        )
      ],
      isLoading: false
    )
  }
}

#Preview {
  NavigationStack {
    AuthorDetailsView(model: .mock)
  }
}
