import Combine
import SwiftUI

struct PlaylistDetailPage: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.editMode) var editMode

  @StateObject var model: Model
  @State private var showDeleteConfirmation = false
  @State private var showEditSheet = false

  var body: some View {
    Group {
      if model.isLoading && model.books.isEmpty {
        ProgressView("Loading playlist...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.books.isEmpty && !model.isLoading {
        ContentUnavailableView(
          "No Books",
          systemImage: "music.note.list",
          description: Text("This playlist is empty.")
        )
      } else {
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
    }
    .listStyle(.plain)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        EditButton()
      }

      ToolbarItem(placement: .navigationBarTrailing) {
        Menu {
          Button {
            showEditSheet = true
          } label: {
            Label("Rename", systemImage: "pencil")
          }

          Button(role: .destructive) {
            showDeleteConfirmation = true
          } label: {
            Label("Delete Playlist", systemImage: "trash")
          }
        } label: {
          Label("More", systemImage: "ellipsis")
        }
        .confirmationDialog(
          "Are you sure you want to remove your playlist \"\(model.playlistName)\"?",
          isPresented: $showDeleteConfirmation,
          titleVisibility: .visible
        ) {
          Button("Delete Playlist", role: .destructive) {
            model.onDeletePlaylist()
          }
          Button("Cancel", role: .cancel) {}
        }
      }
    }
    .refreshable {
      await model.refresh()
    }
    .sheet(isPresented: $showEditSheet) {
      EditPlaylistSheet(
        name: model.playlistName,
        description: model.playlistDescription ?? "",
        onSave: { name, description in
          model.onUpdatePlaylist(name: name, description: description.isEmpty ? nil : description)
        }
      )
    }
    .onAppear {
      model.onAppear()
      if let pageModel = model as? PlaylistDetailPageModel {
        pageModel.onDeleted = { dismiss() }
      }
    }
  }

  private var titleHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 4) {
        Text(model.playlistName.isEmpty ? "Untitled Playlist" : model.playlistName)
          .font(.title2)
          .fontWeight(.bold)
          .foregroundColor(.primary)

        if let description = model.playlistDescription, !description.isEmpty {
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

extension PlaylistDetailPage {
  @Observable
  class Model: ObservableObject {
    var isLoading: Bool
    var playlistName: String
    var playlistDescription: String?
    var books: [ItemRow.Model]

    func onAppear() {}
    func refresh() async {}
    func onDeletePlaylist() {}
    func onUpdatePlaylist(name: String, description: String?) {}
    func onMove(from source: IndexSet, to destination: Int) {}
    func onDelete(at indexSet: IndexSet) {}

    init(
      isLoading: Bool = false,
      playlistName: String = "",
      playlistDescription: String? = nil,
      books: [ItemRow.Model] = []
    ) {
      self.isLoading = isLoading
      self.playlistName = playlistName
      self.playlistDescription = playlistDescription
      self.books = books
    }
  }
}

extension PlaylistDetailPage.Model: Hashable {
  static func == (lhs: PlaylistDetailPage.Model, rhs: PlaylistDetailPage.Model) -> Bool {
    ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

extension PlaylistDetailPage.Model {
  static var mock: PlaylistDetailPage.Model {
    PlaylistDetailPage.Model(
      playlistName: "My Favorites",
      playlistDescription: "My favorite audiobooks to listen to",
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

#Preview("PlaylistDetailPage - Loading") {
  NavigationStack {
    PlaylistDetailPage(model: .init(isLoading: true))
  }
}

#Preview("PlaylistDetailPage - Empty") {
  NavigationStack {
    PlaylistDetailPage(model: .init())
  }
}

#Preview("PlaylistDetailPage - With Books") {
  NavigationStack {
    PlaylistDetailPage(model: .mock)
  }
}
