import API
import Combine
import SwiftUI

struct CollectionDetailPage: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.editMode) var editMode

  @StateObject var model: Model
  @State private var showDeleteConfirmation = false
  @State private var showEditSheet = false

  var body: some View {
    Group {
      if model.isLoading && model.books.isEmpty {
        ProgressView("Loading...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.books.isEmpty && !model.isLoading {
        emptyStateView
      } else {
        listView
      }
    }
    .listStyle(.plain)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if model.canEdit {
        ToolbarItem(placement: .navigationBarTrailing) {
          EditButton()
            .tint(.primary)
        }
      }

      if model.canEdit || model.canDelete {
        ToolbarItem(placement: .navigationBarTrailing) {
          Menu {
            if model.canEdit {
              Button {
                showEditSheet = true
              } label: {
                Label("Rename", systemImage: "pencil")
              }
            }

            if model.canDelete {
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
      return "This playlist is empty."
    case .collections:
      return "This collection is empty."
    }
  }

  private var deleteActionTitle: String {
    switch model.mode {
    case .playlists:
      return "Delete Playlist"
    case .collections:
      return "Delete Collection"
    }
  }

  private var deleteConfirmationMessage: String {
    switch model.mode {
    case .playlists:
      return "Are you sure you want to remove your playlist \"\(model.collectionName)\"?"
    case .collections:
      return "Are you sure you want to remove this collection?"
    }
  }

  private var emptyStateView: some View {
    ContentUnavailableView(
      "No Books",
      systemImage: "music.note.list",
      description: Text(emptyStateMessage)
    )
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
          ZStack {
            NavigationLink(value: NavigationDestination.book(id: book.id)) {
              EmptyView()
            }
            .opacity(editMode?.wrappedValue.isEditing == true ? 0 : 1)
            ItemRow(model: book)
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

      Text("\(model.books.count) \(model.books.count == 1 ? "book" : "books")")
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
    var books: [ItemRow.Model]
    var mode: CollectionMode
    var canEdit: Bool
    var canDelete: Bool

    func onAppear() {}
    func refresh() async {}
    func onDeleteCollection() {}
    func onUpdateCollection(name: String, description: String?) {}
    func onMove(from source: IndexSet, to destination: Int) {}
    func onDelete(at indexSet: IndexSet) {}

    init(
      isLoading: Bool = false,
      collectionName: String = "",
      collectionDescription: String? = nil,
      books: [ItemRow.Model] = [],
      mode: CollectionMode = .playlists,
      canEdit: Bool = false,
      canDelete: Bool = false
    ) {
      self.isLoading = isLoading
      self.collectionName = collectionName
      self.collectionDescription = collectionDescription
      self.books = books
      self.mode = mode
      self.canEdit = canEdit
      self.canDelete = canDelete
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
        ItemRow.Model(
          id: "1",
          title: "The Name of the Wind",
          details: "Patrick Rothfuss",
          coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")!,
          progress: 0.45
        ),
        ItemRow.Model(
          id: "2",
          title: "Project Hail Mary",
          details: "Andy Weir",
          coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")!,
          progress: 0.0
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
