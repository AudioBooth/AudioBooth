import Audiobookshelf
import Combine
import SwiftUI

struct RecentRow: View {
  @Bindable var model: Model

  @State private var showingDeleteConfirmation = false

  var body: some View {
    Button(action: {
      model.onTapped()
    }) {
      HStack(spacing: 8) {
        cover

        VStack(alignment: .leading, spacing: 16) {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
              title
              author
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu(
              content: { contextMenu },
              label: {
                Image(systemName: "ellipsis")
                  .font(.headline)
                  .foregroundColor(.primary)
                  .padding(.vertical, 10)
                  .padding(.leading, 4)
                  .contentShape(Rectangle())
              }
            )
          }

          if let timeRemaining = model.timeRemaining {
            Text("\(timeRemaining)")
              .font(.caption)
              .foregroundColor(.secondary)
          }

          progressInfo
        }
      }
      .padding()
      .contentShape(Rectangle())
    }
    .contextMenu { contextMenu }
    .onAppear(perform: model.onAppear)
    .alert("Remove from continue listening", isPresented: $showingDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Remove", role: .destructive) {
        model.onDeleteTapped(isFileOnly: false)
      }
    } message: {
      Text(
        "This book has offline files. Removing it from continue listening will also remove the offline capability for this book."
      )
    }
  }

  var cover: some View {
    LazyImage(url: model.coverURL) { state in
      if let image = state.image {
        image
          .resizable()
          .aspectRatio(1, contentMode: .fit)
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.gray.opacity(0.3))
          .aspectRatio(1, contentMode: .fit)
          .overlay {
            Image(systemName: "book.closed")
              .foregroundColor(.gray)
              .font(.title2)
          }
      }
    }
    .frame(width: 100, height: 100)
    .overlay(alignment: .bottom) {
      progressBar
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  var title: some View {
    Text(model.title)
      .font(.headline)
      .lineLimit(2)
      .foregroundColor(.primary)
      .multilineTextAlignment(.leading)
  }

  @ViewBuilder
  var author: some View {
    if let author = model.author {
      Text(author)
        .font(.subheadline)
        .foregroundColor(.secondary)
        .lineLimit(1)
    }
  }

  var progressInfo: some View {
    HStack {
      source

      if let progress = model.progress {
        Text(progress.formatted(.percent.precision(.fractionLength(0))))
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      if let lastPlayed = model.lastPlayed {
        Text(lastPlayed)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  var source: some View {
    HStack(spacing: 8) {
      switch model.downloadState {
      case .downloading:
        Image(systemName: "internaldrive.fill")
          .font(.caption)
          .foregroundColor(.blue)
          .hidden()
          .overlay {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .blue))
              .scaleEffect(0.7)
          }
      case .downloaded:
        Image(systemName: "internaldrive.fill")
          .font(.caption)
          .foregroundColor(.blue)
      case .notDownloaded:
        Image(systemName: "icloud.and.arrow.down")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  @ViewBuilder
  var contextMenu: some View {
    switch model.downloadState {
    case .downloading:
      Button {
        model.onDownloadTapped()
      } label: {
        Label("Cancel Download", systemImage: "stop.circle")
      }
    case .notDownloaded:
      Button {
        model.onDownloadTapped()
      } label: {
        Label("Download", systemImage: "icloud.and.arrow.down")
      }
    case .downloaded:
      Button(role: .destructive) {
        model.onDeleteTapped(isFileOnly: true)
      } label: {
        Label("Remove from Device", systemImage: "trash")
      }
    }

    Button {
      if model.downloadState == .downloaded {
        showingDeleteConfirmation = true
      } else {
        model.onDeleteTapped(isFileOnly: false)
      }
    } label: {
      Label("Remove from continue listening", systemImage: "eye.slash")
    }
  }

  @ViewBuilder
  var progressBar: some View {
    if let progress = model.progress, progress > 0 {
      GeometryReader { geometry in
        let progressColor: Color = progress >= 1.0 ? .green : .orange

        RoundedRectangle(cornerRadius: 2)
          .fill(progressColor)
          .frame(width: geometry.size.width * progress, height: 4)
      }
      .frame(height: 4)
    }
  }

}

extension RecentRow {
  @Observable class Model {
    let id: String
    let title: String
    let author: String?
    let coverURL: URL?
    let progress: Double?
    let lastPlayed: String?
    let timeRemaining: String?

    var downloadState: DownloadManager.DownloadState

    @MainActor func onAppear() {}
    @MainActor func onTapped() {}
    @MainActor func onDeleteTapped(isFileOnly: Bool) {}
    @MainActor func onDownloadTapped() {}

    init(
      id: String = UUID().uuidString,
      title: String,
      author: String?,
      coverURL: URL?,
      progress: Double?,
      lastPlayed: String?,
      timeRemaining: String? = nil,
      downloadState: DownloadManager.DownloadState = .notDownloaded
    ) {
      self.id = id
      self.title = title
      self.author = author
      self.coverURL = coverURL
      self.progress = progress
      self.lastPlayed = lastPlayed
      self.timeRemaining = timeRemaining
      self.downloadState = downloadState
    }
  }
}

extension RecentRow.Model {
  static let mock = RecentRow.Model(
    title: "The Lord of the Rings",
    author: "J.R.R. Tolkien",
    coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
    progress: 0.45,
    lastPlayed: Date().addingTimeInterval(-3600).formatted(.relative(presentation: .named)),
    timeRemaining: "8hr 32min remaining"
  )
}

#Preview("RecentRow") {
  ScrollView {
    RecentRow(model: .mock)
      .padding()
  }
}
