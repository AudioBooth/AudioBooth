import API
import Combine
import SwiftUI

struct CollectionDetailPage: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject private var preferences = UserPreferences.shared

  @StateObject var model: Model
  @State private var showDeleteConfirmation = false
  @State private var showEditSheet = false

  private var isCardMode: Bool {
    preferences.libraryDisplayMode == .card
  }

  var body: some View {
    Group {
      if model.isLoading && model.books.isEmpty {
        ProgressView("Loading...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.books.isEmpty && !model.isLoading {
        emptyStateView
      } else if isCardMode {
        cardView
      } else {
        listView
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if model.mode == .playlists {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            model.onTogglePin()
          } label: {
            Image(systemName: model.isPinned ? "pin.fill" : "pin")
          }
          .tint(.primary)
        }
      }

      if model.canEdit && !isCardMode {
        ToolbarItem(placement: .topBarTrailing) {
          EditButton()
            .tint(.primary)
        }
      }

      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Toggle(
            isOn: Binding(
              get: { preferences.libraryDisplayMode == .card },
              set: { if $0 { preferences.libraryDisplayMode = .card } }
            )
          ) {
            Label("Grid View", systemImage: "square.grid.2x2")
          }

          Toggle(
            isOn: Binding(
              get: { preferences.libraryDisplayMode == .row },
              set: { if $0 { preferences.libraryDisplayMode = .row } }
            )
          ) {
            Label("List View", systemImage: "rectangle.grid.1x3")
          }

          if model.canEdit {
            Divider()

            Button {
              showEditSheet = true
            } label: {
              Label("Rename", systemImage: "pencil")
            }
          }

          if model.canDelete {
            Divider()

            Button(role: .destructive) {
              showDeleteConfirmation = true
            } label: {
              Label(deleteActionTitle, systemImage: "trash")
            }
            .tint(.red)
          }
        } label: {
          Label("More", systemImage: "ellipsis")
        }
        .confirmationDialog(
          deleteConfirmationMessage,
          isPresented: $showDeleteConfirmation,
          titleVisibility: .visible
        ) {
          Button(deleteActionTitle, role: .destructive) {
            model.onDeleteCollection()
          }
          Button("Cancel", role: .cancel) {}
        }
        .tint(.primary)
      }
    }
    .refreshable {
      await model.refresh()
    }
    .sheet(isPresented: $showEditSheet) {
      EditPlaylistSheet(
        name: model.collectionName,
        description: model.collectionDescription ?? "",
        onSave: { name, description in
          model.onUpdateCollection(name: name, description: description.isEmpty ? nil : description)
        }
      )
    }
    .onAppear {
      model.onAppear()
      if let pageModel = model as? CollectionDetailPageModel {
        pageModel.onDeleted = { dismiss() }
      }
    }
  }

  private var emptyStateMessage: String {
    switch model.mode {
    case .playlists:
      String(localized: "This playlist is empty.")
    case .collections:
      String(localized: "This collection is empty.")
    }
  }

  private var deleteActionTitle: String {
    switch model.mode {
    case .playlists:
      String(localized: "Delete Playlist")
    case .collections:
      String(localized: "Delete Collection")
    }
  }

  private var deleteConfirmationMessage: String {
    switch model.mode {
    case .playlists:
      String(localized: "Are you sure you want to remove your playlist \"\(model.collectionName)\"?")
    case .collections:
      String(localized: "Are you sure you want to remove this collection?")
    }
  }

  private var emptyStateView: some View {
    ContentUnavailableView(
      "No Books",
      systemImage: "music.note.list",
      description: Text(emptyStateMessage)
    )
  }

  private var cardView: some View {
    ScrollView {
      VStack(alignment: .leading) {
        titleHeader

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 100), spacing: 20)],
          spacing: 20
        ) {
          ForEach(model.books) { book in
            BookCard(model: book)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          }
        }
        .padding(.horizontal)
      }
    }
    .environment(\.itemDisplayMode, .card)
  }

  private var listView: some View {
    List {
      Section {
        titleHeader
      }
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)

      Section {
        ForEach(model.books) { book in
          if book.podcastID != nil {
            episodeRow(book)
          } else {
            BookListCard(model: book)
          }
        }
        .onMove { source, destination in
          model.onMove(from: source, to: destination)
        }
        .onDelete { indexSet in
          model.onDelete(at: indexSet)
        }
      }
    }
    .listStyle(.plain)
    .environment(\.itemDisplayMode, .row)
  }

  private func episodeRow(_ book: BookCard.Model) -> some View {
    HStack(spacing: 12) {
      Cover(model: book.cover, size: .small)
        .frame(width: 60, height: 60)

      VStack(alignment: .leading, spacing: 6) {
        Text(book.title)
          .font(.caption)
          .foregroundColor(.primary)
          .fontWeight(.medium)
          .lineLimit(1)

        if let author = book.author {
          Text(author)
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }

        if let details = book.details {
          Text(details)
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        model.onPlayItem(book)
      } label: {
        Image(systemName: "play.fill")
          .font(.title3)
          .foregroundStyle(Color.accentColor)
      }
      .buttonStyle(.plain)
    }
    .contentShape(Rectangle())
    .overlay {
      NavigationLink(value: NavigationDestination.podcast(id: book.podcastID ?? book.id)) {}
        .opacity(0)
    }
  }

  private var titleHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        Text(model.collectionName.isEmpty ? "Untitled" : model.collectionName)
          .font(.title2)
          .fontWeight(.bold)
          .foregroundColor(.primary)

        if let description = model.collectionDescription, !description.isEmpty {
          Text(description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }
      }

      Text("^[\(model.books.count) item](inflect: true)")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

extension CollectionDetailPage {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool
    var collectionName: String
    var collectionDescription: String?
    var books: [BookCard.Model]
    var mode: CollectionMode
    var canEdit: Bool
    var canDelete: Bool
    var isPinned: Bool

    func onAppear() {}
    func refresh() async {}
    func onDeleteCollection() {}
    func onUpdateCollection(name: String, description: String?) {}
    func onMove(from source: IndexSet, to destination: Int) {}
    func onDelete(at indexSet: IndexSet) {}
    func onTogglePin() {}
    func onPlayItem(_ item: BookCard.Model) {}

    init(
      isLoading: Bool = false,
      collectionName: String = "",
      collectionDescription: String? = nil,
      books: [BookCard.Model] = [],
      mode: CollectionMode = .playlists,
      canEdit: Bool = false,
      canDelete: Bool = false,
      isPinned: Bool = false
    ) {
      self.isLoading = isLoading
      self.collectionName = collectionName
      self.collectionDescription = collectionDescription
      self.books = books
      self.mode = mode
      self.canEdit = canEdit
      self.canDelete = canDelete
      self.isPinned = isPinned
    }
  }
}

extension CollectionDetailPage.Model: Hashable {
  static func == (lhs: CollectionDetailPage.Model, rhs: CollectionDetailPage.Model) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

extension CollectionDetailPage.Model {
  static var mock: CollectionDetailPage.Model {
    CollectionDetailPage.Model(
      collectionName: "My Favorites",
      collectionDescription: "My favorite audiobooks to listen to",
      books: [
        BookCard.Model(
          id: "1",
          title: "The Name of the Wind",
          cover: Cover.Model(
            url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
            progress: 0.45
          ),
          author: "Patrick Rothfuss"
        ),
        BookCard.Model(
          id: "2",
          title: "Project Hail Mary",
          cover: Cover.Model(
            url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")
          ),
          author: "Andy Weir"
        ),
      ]
    )
  }
}

#Preview("CollectionDetailPage - Loading") {
  NavigationStack {
    CollectionDetailPage(model: .init(isLoading: true))
  }
}

#Preview("CollectionDetailPage - Empty") {
  NavigationStack {
    CollectionDetailPage(model: .init())
  }
}

#Preview("CollectionDetailPage - With Books") {
  NavigationStack {
    CollectionDetailPage(model: .mock)
  }
}
