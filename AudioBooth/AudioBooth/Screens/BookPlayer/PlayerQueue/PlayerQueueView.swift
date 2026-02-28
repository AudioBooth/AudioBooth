import Combine
import SwiftUI

struct PlayerQueueView: View {
  @ObservedObject var model: Model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        if let currentItem = model.currentItem {
          Section("Now Playing") {
            CurrentRow(
              item: currentItem,
              onTapped: {
                dismiss()
                PlayerManager.shared.showFullPlayer()
              },
              onClear: model.onClearCurrentTapped
            )
          }
        }

        Section {
          if model.queue.isEmpty {
            ContentUnavailableView(
              "Queue is Empty",
              systemImage: "text.badge.plus",
              description: Text("Add books to the queue from the library")
            )
            .listRowBackground(Color.clear)
          } else {
            ForEach(model.queue) { item in
              QueueRow(item: item) {
                model.onPlayTapped(item)
              }
            }
            .onDelete(perform: model.onDelete)
            .onMove(perform: model.onMove)
          }
        } header: {
          HStack {
            Text("Up Next")
            Spacer()
            if !model.queue.isEmpty {
              Button("Clear", role: .destructive, action: model.onClearQueueTapped)
            }
          }
        } footer: {
          if !model.queue.isEmpty {
            Text("Swipe to remove or drag to reorder")
          }
        }
      }
      .navigationTitle("Queue")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark", action: { dismiss() })
            .tint(.primary)
        }

        if !model.queue.isEmpty {
          ToolbarItem(placement: .primaryAction) {
            EditButton()
              .tint(.primary)
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        Toggle("Auto-play next", isOn: $model.autoPlayNext)
          .padding()
          .font(.subheadline)
          .bold()
          .background(.regularMaterial)
      }
      .navigationDestination(for: NavigationDestination.self) { destination in
        switch destination {
        case .book(let id):
          BookDetailsView(model: BookDetailsViewModel(bookID: id))
        case .series, .author, .narrator, .genre, .tag, .offline, .authorLibrary:
          LibraryPage(model: LibraryPageModel(destination: destination))
        case .podcast(let id, let episodeID):
          PodcastDetailsView(model: PodcastDetailsViewModel(podcastID: id, episodeID: episodeID))
        case .playlist, .collection, .stats:
          EmptyView()
        }
      }
    }
  }
}

extension PlayerQueueView {
  struct CurrentRow: View {
    @Environment(\.editMode) private var editMode

    let item: QueueItem
    let onTapped: () -> Void
    let onClear: () -> Void

    private var isEditing: Bool {
      editMode?.wrappedValue.isEditing ?? false
    }

    var body: some View {
      HStack {
        cover
        info
        trailingButton
      }
      .contentShape(Rectangle())
      .overlay {
        if !isEditing {
          NavigationLink(value: queueDestination(for: item)) {}
            .opacity(0)
        }
      }
    }

    private var cover: some View {
      Cover(url: item.coverURL)
        .frame(width: 40, height: 40)
    }

    private var info: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.footnote)
          .fontWeight(.medium)
          .foregroundColor(.primary)
          .lineLimit(1)

        if let details = item.details {
          Text(details)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var trailingButton: some View {
      if isEditing {
        Button(action: onClear) {
          Image(systemName: "xmark")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .padding(8)
            .background(Color.secondary.opacity(0.2))
            .clipShape(.circle)
        }
        .buttonStyle(.borderless)
      }
    }
  }

  struct QueueRow: View {
    @Environment(\.editMode) private var editMode

    @ObservedObject private var preferences = UserPreferences.shared

    let item: QueueItem
    let onPlay: () -> Void

    private var isEditing: Bool {
      editMode?.wrappedValue.isEditing ?? false
    }

    var body: some View {
      HStack {
        cover
        info
        if !isEditing {
          playButton
        }
      }
      .contentShape(Rectangle())
      .overlay {
        if !isEditing {
          NavigationLink(value: queueDestination(for: item)) {}
            .opacity(0)
        }
      }
    }

    private var cover: some View {
      Cover(url: item.coverURL)
        .frame(width: 40, height: 40)
    }

    private var info: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.footnote)
          .fontWeight(.medium)
          .foregroundColor(.primary)
          .lineLimit(1)

        if let details = item.details {
          Text(details)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playButton: some View {
      Button(action: onPlay) {
        Image(systemName: "play.fill")
          .font(.system(size: 10))
          .aspectRatio(1, contentMode: .fit)
          .foregroundColor(.white)
          .padding(10)
          .background(preferences.accentColor)
          .clipShape(.circle)
      }
      .buttonStyle(.borderless)
    }
  }
}

extension PlayerQueueView {
  @Observable
  class Model: ObservableObject {
    var currentItem: QueueItem?
    var queue: [QueueItem]
    var autoPlayNext: Bool

    func onDelete(at offsets: IndexSet) {}
    func onMove(from source: IndexSet, to destination: Int) {}
    func onPlayTapped(_ item: QueueItem) {}
    func onClearCurrentTapped() {}
    func onClearQueueTapped() {}

    init(
      currentItem: QueueItem? = nil,
      queue: [QueueItem] = [],
      autoPlayNext: Bool = true,
      isPlaying: Bool = false
    ) {
      self.currentItem = currentItem
      self.queue = queue
      self.autoPlayNext = autoPlayNext
    }
  }
}

#Preview {
  PlayerQueueView(
    model: PlayerQueueView.Model(
      currentItem: QueueItem(
        from: PreviewBook(
          id: "1",
          title: "Current Book",
          details: "Author Name",
          coverURL: nil
        )
      ),
      queue: [
        QueueItem(
          from: PreviewBook(
            id: "2",
            title: "Next Book",
            details: "Another Author",
            coverURL: nil
          )
        ),
        QueueItem(
          from: PreviewBook(
            id: "3",
            title: "Third Book",
            details: "Third Author",
            coverURL: nil
          )
        ),
      ]
    )
  )
}

private func queueDestination(for item: QueueItem) -> NavigationDestination {
  if let podcastID = item.podcastID {
    return .podcast(id: podcastID, episodeID: item.bookID)
  }
  return .book(id: item.bookID)
}

private struct PreviewBook: BookActionable {
  let id: String
  let title: String
  let details: String?
  let coverURL: URL?

  var bookID: String { id }
}
