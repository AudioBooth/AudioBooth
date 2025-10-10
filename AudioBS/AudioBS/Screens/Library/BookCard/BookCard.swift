import API
import Combine
import SwiftUI

struct BookCard: View {
  @Environment(\.navigationPath) private var navigationPath

  @StateObject var model: Model

  var body: some View {
    Button {
      if case .downloading = model.downloadState {
        model.onCancelDownloadTapped()
      } else {
        navigationPath?.wrappedValue.append(NavigationDestination.book(id: model.id))
      }
    } label: {
      content
    }
    .buttonStyle(.plain)
    .contextMenu { contextMenu }
    .onAppear(perform: model.onAppear)
    .onDisappear(perform: model.onDisappear)
  }

  var content: some View {
    VStack(alignment: .leading, spacing: 8) {
      cover

      VStack(alignment: .leading, spacing: 4) {
        title
        details
      }
      .multilineTextAlignment(.leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .topTrailing) {
      if let sequence = model.sequence {
        Text("#\(sequence)")
          .font(.caption2)
          .foregroundStyle(Color.white)
          .padding(.vertical, 2)
          .padding(.horizontal, 4)
          .background(Color.black.opacity(0.6))
          .clipShape(Capsule())
          .padding(4)
      }
    }
    .contentShape(Rectangle())
  }

  var cover: some View {
    CoverImage(url: model.coverURL)
      .overlay(alignment: .bottom) { progressBar }
      .overlay {
        if case .downloading(let progress) = model.downloadState {
          Color.black.opacity(0.6).overlay {
            ProgressView(value: progress, total: 1.0)
              .progressViewStyle(GaugeProgressViewStyle(lineWidth: 5))
              .frame(width: 50, height: 50)
              .overlay {
                Color.blue.padding()
              }
          }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(.gray.opacity(0.3), lineWidth: 1)
      )
      .contentShape(Rectangle())
  }

  var title: some View {
    Text(model.title)
      .font(.caption)
      .foregroundColor(.primary)
      .fontWeight(.medium)
      .lineLimit(1)
      .allowsTightening(true)
  }

  @ViewBuilder
  var details: some View {
    if let details = model.details {
      Text(details)
        .font(.caption2)
        .foregroundColor(.secondary)
        .lineLimit(1)
        .allowsTightening(true)
    }
  }

  @ViewBuilder
  var progressBar: some View {
    if let progress = model.progress, progress > 0 {
      GeometryReader { geometry in
        let progressColor: Color = progress >= 1.0 ? .green : .orange

        Rectangle()
          .fill(progressColor)
          .frame(width: geometry.size.width * progress, height: 4)
      }
      .frame(height: 4)
    }
  }

  @ViewBuilder
  var contextMenu: some View {
    if let downloadState = model.downloadState {
      switch downloadState {
      case .downloaded:
        Button(role: .destructive) {
          model.onRemoveFromDeviceTapped()
        } label: {
          Label("Remove from Device", systemImage: "trash")
        }
      case .downloading:
        Button(role: .destructive) {
          model.onCancelDownloadTapped()
        } label: {
          Label("Cancel Download", systemImage: "xmark.circle")
        }
      case .notDownloaded:
        Button {
          model.onDownloadTapped()
        } label: {
          Label("Download", systemImage: "icloud.and.arrow.down")
        }
      }
    } else {
      Button {
        model.onDownloadTapped()
      } label: {
        Label("Download", systemImage: "icloud.and.arrow.down")
      }
    }

    if let progress = model.progress, progress >= 1.0 {
      Button {
        model.onMarkFinishedTapped(isFinished: false)
      } label: {
        Label("Mark as Not Finished", systemImage: "checkmark.circle.fill")
      }
    } else {
      Button {
        model.onMarkFinishedTapped(isFinished: true)
      } label: {
        Label("Mark as Finished", systemImage: "checkmark.circle")
      }
    }
  }
}

extension BookCard {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id: String
    let title: String
    let details: String?
    let coverURL: URL?
    let sequence: String?
    var progress: Double?
    var downloadState: DownloadManager.DownloadState?

    func onAppear() {}
    func onDisappear() {}

    func onDownloadTapped() {}
    func onCancelDownloadTapped() {}
    func onRemoveFromDeviceTapped() {}
    func onMarkFinishedTapped(isFinished: Bool) {}

    init(
      id: String = UUID().uuidString,
      title: String,
      details: String?,
      coverURL: URL?,
      sequence: String? = nil,
      progress: Double? = nil,
      downloadState: DownloadManager.DownloadState? = nil
    ) {
      self.id = id
      self.title = title
      self.details = details
      self.coverURL = coverURL
      self.sequence = sequence
      self.progress = progress
      self.downloadState = downloadState
    }
  }
}

extension BookCard.Model {
  static let mock = BookCard.Model(
    title: "The Lord of the Rings",
    details: "J.R.R. Tolkien",
    coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg")
  )
}

#Preview("BookCard") {
  NavigationStack {
    LazyVGrid(
      columns: [
        GridItem(spacing: 12, alignment: .top),
        GridItem(spacing: 12, alignment: .top),
        GridItem(spacing: 12, alignment: .top),
      ],
      spacing: 20,
    ) {
      BookCard(
        model: BookCard.Model(
          title: "The Lord of the Rings",
          details: "J.R.R. Tolkien",
          coverURL: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
          downloadState: .downloading(progress: 0.5)
        )
      )
      BookCard(
        model: BookCard.Model(
          title: "Dune",
          details: "Frank Herbert",
          coverURL: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg")
        )
      )
      BookCard(
        model: BookCard.Model(
          title: "The Foundation",
          details: "Isaac Asimov",
          coverURL: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg")
        )
      )
    }
    .padding()
  }
}
