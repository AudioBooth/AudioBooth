import Combine
import SwiftUI

struct StoragePreferencesView: View {
  @ObservedObject var model: Model
  @ObservedObject private var preferences = UserPreferences.shared

  var body: some View {
    Form {
      Section {
        HStack {
          Text("Total Storage Used")
          Spacer()
          if model.isLoading {
            ProgressView()
          } else {
            Text(model.totalSize)
              .foregroundStyle(.secondary)
          }
        }
      }

      Section("Download Settings") {
        Picker("Auto-Download Books", selection: $preferences.autoDownloadBooks) {
          ForEach(AutoDownloadMode.allCases, id: \.rawValue) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .font(.subheadline)
        .bold()

        if preferences.autoDownloadBooks != .off {
          Picker("Delay Before Download", selection: $preferences.autoDownloadDelay) {
            ForEach(AutoDownloadDelay.allCases, id: \.rawValue) { delay in
              Text(delay.displayName).tag(delay)
            }
          }
          .font(.subheadline)
          .bold()
        }

        Toggle("Remove Download on Completion", isOn: $preferences.removeDownloadOnCompletion)
          .font(.subheadline)
          .bold()
      }

      Section("Storage Limits") {
        Picker("Maximum Storage", selection: $preferences.maxDownloadStorage) {
          ForEach(MaxDownloadStorage.allCases, id: \.rawValue) { limit in
            Text(limit.displayName).tag(limit)
          }
        }
        .font(.subheadline)
        .bold()

        Picker("Remove After Unused For", selection: $preferences.removeAfterUnused) {
          ForEach(RemoveAfterUnused.allCases, id: \.rawValue) { duration in
            Text(duration.displayName).tag(duration)
          }
        }
        .font(.subheadline)
        .bold()
      }

      downloadContent

      Section("Image Cache") {
        HStack {
          Text("Cache Size")
          Spacer()
          if model.isLoading {
            ProgressView()
          } else {
            Text(model.cacheSize)
              .foregroundStyle(.secondary)
          }
        }

        Button("Clear Image Cache", action: model.onClearCacheTapped)
          .foregroundColor(.red)
          .disabled(model.cacheSize == "0 bytes" || model.isLoading)

        Text("Cover images will be re-downloaded as needed.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Storage")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: model.onAppear)
    .alert("Clear All Downloads?", isPresented: $model.showDownloadConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Clear", role: .destructive, action: model.onConfirmClearDownloads)
    } message: {
      Text("This will delete all downloaded content. This action cannot be undone.")
    }
    .alert("Clear Image Cache?", isPresented: $model.showCacheConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Clear", role: .destructive, action: model.onConfirmClearCache)
    } message: {
      Text("This will clear all cached cover images. They will be re-downloaded as needed.")
    }
  }

  @ViewBuilder
  var downloadContent: some View {
    if !model.serverDownloads.isEmpty {
      Section("Downloaded Content") {
        NavigationLink {
          DownloadedBooksView(model: model)
        } label: {
          HStack {
            Text("Audiobooks & Ebooks")
            Spacer()
            if model.isLoading {
              ProgressView()
            } else {
              Text(model.downloadSize)
                .foregroundStyle(.secondary)
            }
          }
        }

        Button("Clear All Downloads", action: model.onClearDownloadsTapped)
          .foregroundColor(.red)
          .disabled(model.downloadSize == "0 bytes" || model.isLoading)

        Text("This will delete all downloaded audiobooks and ebooks. You can re-download them later.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

extension StoragePreferencesView {
  struct ServerDownloads: Identifiable {
    let id: String
    let name: String
    var books: [DownloadedBook]
  }

  struct DownloadedBook: Identifiable {
    let id: String
    let serverID: String
    let title: String
    let author: String?
    let size: String
  }

  @Observable class Model: ObservableObject {
    var isLoading = true
    var totalSize = "0 bytes"
    var downloadSize = "0 bytes"
    var cacheSize = "0 bytes"
    var showDownloadConfirmation = false
    var showCacheConfirmation = false
    var serverDownloads: [ServerDownloads] = []

    func onAppear() {}
    func onClearDownloadsTapped() {}
    func onClearCacheTapped() {}
    func onConfirmClearDownloads() {}
    func onConfirmClearCache() {}
    func onRemoveDownload(bookID: String, serverID: String) {}

    init(
      isLoading: Bool = true,
      totalSize: String = "0 bytes",
      downloadSize: String = "0 bytes",
      cacheSize: String = "0 bytes",
      serverDownloads: [ServerDownloads] = []
    ) {
      self.isLoading = isLoading
      self.totalSize = totalSize
      self.downloadSize = downloadSize
      self.cacheSize = cacheSize
      self.serverDownloads = serverDownloads
    }
  }
}

extension StoragePreferencesView.Model {
  static var mock = StoragePreferencesView.Model(
    isLoading: false,
    totalSize: "1.2 GB",
    downloadSize: "800 MB",
    cacheSize: "400 MB"
  )
}

private struct DownloadedBooksView: View {
  @ObservedObject var model: StoragePreferencesView.Model

  var body: some View {
    List {
      ForEach(model.serverDownloads) { server in
        Section(server.name) {
          ForEach(server.books) { book in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                  .font(.subheadline)
                if let author = book.author {
                  Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              Spacer()
              Text(book.size)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) {
                model.onRemoveDownload(bookID: book.id, serverID: book.serverID)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
          }
        }
      }
    }
    .navigationTitle("Downloaded Books")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    StoragePreferencesView(model: .mock)
  }
}
