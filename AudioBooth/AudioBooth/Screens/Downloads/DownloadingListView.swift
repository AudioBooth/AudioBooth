import Combine
import SwiftUI

struct DownloadingListView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject var model: Model

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        ForEach(model.books) { book in
          NavigationLink(value: NavigationDestination.book(id: book.id)) {
            Row(
              book: book,
              onCancel: { model.onCancelDownload(bookID: book.id) },
              onResume: { model.onResumeDownload(bookID: book.id) },
              onRemove: { model.onRemoveDownload(bookID: book.id) }
            )
          }
        }
      }
    }
    .background(theme.colors.background.page)
    .navigationTitle("Downloading")
    .onAppear(perform: model.onAppear)
  }
}

extension DownloadingListView {
  struct Row: View {
    let book: BookItem
    let onCancel: () -> Void
    let onResume: () -> Void
    let onRemove: () -> Void

    @ScaledMetric(relativeTo: .title) private var coverSize: CGFloat = 60

    var body: some View {
      HStack(spacing: 12) {
        cover

        VStack(alignment: .leading, spacing: 6) {
          Text(book.title)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .allowsTightening(true)

          if let details = book.details {
            Text(verbatim: details)
              .font(.caption2)
              .lineLimit(1)
          }

          HStack {
            ProgressView(value: book.progress)
              .tint(book.status == .downloading ? .accentColor : .secondary)

            switch book.status {
            case .downloading:
              Text(book.progress.formatted(.percent.precision(.fractionLength(0))))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            case .queued:
              EmptyView()
            case .failed:
              Label("Paused", systemImage: "pause.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        switch book.status {
        case .downloading:
          Button(action: onCancel) {
            Image(systemName: "stop.circle")
              .font(.title2)
          }
          .buttonStyle(.plain)

        case .queued:
          Button(action: onCancel) {
            Image(systemName: "xmark.circle")
              .font(.title2)
          }
          .buttonStyle(.plain)

        case .failed:
          Button(action: onResume) {
            Image(systemName: "arrow.down.circle")
              .font(.title2)
          }
          .buttonStyle(.plain)

          Button(action: onRemove) {
            Image(systemName: "trash")
              .font(.title2)
          }
          .buttonStyle(.plain)
        }
      }
      .foregroundColor(.primary)
      .padding(.horizontal)
      .contentShape(Rectangle())
    }

    var cover: some View {
      Cover(url: book.coverURL)
        .frame(width: coverSize, height: coverSize)
    }
  }
}

extension DownloadingListView {
  struct BookItem: Identifiable {
    enum Status {
      case downloading
      case queued
      case failed
    }

    let id: String
    let title: String
    var details: String?
    let coverURL: URL?
    let duration: TimeInterval
    let totalSize: Int64
    var progress: Double
    var status: Status
  }

  @Observable
  class Model: ObservableObject {
    var books: [BookItem]

    func onAppear() {}
    func onCancelDownload(bookID: String) {}
    func onResumeDownload(bookID: String) {}
    func onRemoveDownload(bookID: String) {}

    init(books: [BookItem] = []) {
      self.books = books
    }
  }
}
