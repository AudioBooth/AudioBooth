import Combine
import SwiftUI

struct StoragePreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject var model: Model
  @ObservedObject private var preferences = UserPreferences.shared

  private let storageOptions: [Int] = [1, 2, 5, 10, 20, 50, 0]
  private let removeAfterOptions: [RemoveAfterUnused] = [
    .oneDay, .fiveDays, .sevenDays, .fourteenDays, .thirtyDays, .ninetyDays, .oneHundredEightyDays, .never,
  ]

  @State private var maxStorageGB: Int = UserPreferences.shared.maxDownloadStorageGB
  @State private var removeAfter: RemoveAfterUnused = UserPreferences.shared.removeAfterUnused

  private var maxStorageLabel: String {
    maxStorageGB == 0 ? String(localized: "Unlimited") : "\(maxStorageGB) GB"
  }

  var body: some View {
    Form {
      Section {
        StorageBreakdownCard(model: model)
          .listRowInsets(EdgeInsets())
          .listRowBackground(theme.colors.background.card)
      }

      Section {
        Picker(selection: $preferences.autoDownloadBooks) {
          ForEach(AutoDownloadMode.allCases, id: \.rawValue) { mode in
            Text(mode.displayName).tag(mode)
          }
        } label: {
          PreferenceRow(
            systemImage: "arrow.down.circle",
            tint: .green,
            title: "Auto-Download Books",
            subtitle: "Pull new books over automatically"
          )
        }
        .listRowBackground(theme.colors.background.card)

        if preferences.autoDownloadBooks != .off {
          Picker(selection: $preferences.autoDownloadDelay) {
            ForEach(AutoDownloadDelay.allCases, id: \.rawValue) { delay in
              Text(delay.displayName).tag(delay)
            }
          } label: {
            PreferenceRow(
              systemImage: "clock",
              tint: .blue,
              title: "Delay Before Download"
            )
          }
          .listRowBackground(theme.colors.background.card)
        }

        Toggle(isOn: $preferences.autoDownloadQueuedEpisodes) {
          PreferenceRow(
            systemImage: "text.badge.plus",
            tint: .teal,
            title: "Auto-Download Queued Episodes",
            subtitle: "Download episodes auto-added to the queue"
          )
        }
        .listRowBackground(theme.colors.background.card)

        Toggle(isOn: $preferences.removeDownloadOnCompletion) {
          PreferenceRow(
            systemImage: "trash",
            tint: .orange,
            title: "Remove After Completion",
            subtitle: "Free up space when finished"
          )
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Downloads")
      }

      Section {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Maximum Storage")
                .font(.subheadline)
                .fontWeight(.medium)
              Text("Cap total downloaded size")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(maxStorageLabel)
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(Color.accentColor)
          }
          TickSlider(
            value: Binding(
              get: { Double(maxStorageGB) },
              set: { maxStorageGB = Int($0) }
            ),
            ticks: storageOptions.map(Double.init)
          )
          .accessibilityValue(maxStorageLabel)
        }
        .listRowBackground(theme.colors.background.card)

        VStack(alignment: .leading, spacing: 12) {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Remove After Unused For")
                .font(.subheadline)
                .fontWeight(.medium)
              Text("Auto-clean books you haven't opened")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(removeAfter.displayName)
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(Color.accentColor)
          }
          TickSlider(
            value: Binding(
              get: { Double(removeAfter.rawValue) },
              set: { newValue in
                if let match = removeAfterOptions.first(where: { $0.rawValue == Int(newValue) }) {
                  removeAfter = match
                }
              }
            ),
            ticks: removeAfterOptions.map { Double($0.rawValue) }
          )
          .accessibilityValue(removeAfter.displayName)
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Limits")
      }

      Section {
        if !model.serverDownloads.isEmpty {
          NavigationLink {
            DownloadedBooksView(model: model)
          } label: {
            HStack {
              PreferenceRow(
                systemImage: "books.vertical.fill",
                tint: .blue,
                title: "Audiobooks & Ebooks"
              )
              Spacer()
              chip(text: model.downloadSize)
            }
          }
          .listRowBackground(theme.colors.background.card)
        }

        HStack {
          PreferenceRow(
            systemImage: "sparkles",
            tint: .purple,
            title: "Image Cache"
          )
          Spacer()
          chip(text: model.cacheSize)
        }
        .listRowBackground(theme.colors.background.card)

        Button(action: model.onClearDownloadsTapped) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Clear All Downloads")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.red)
            Text("Re-download anytime")
              .font(.caption)
              .tint(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowBackground(theme.colors.background.card)
        .disabled(model.serverDownloads.isEmpty || model.isLoading)

        Button(action: model.onClearCacheTapped) {
          Text("Clear Image Cache")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowBackground(theme.colors.background.card)
        .disabled(model.imageCacheBytes == 0 || model.isLoading)
      } header: {
        Text("Manage")
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle("Storage")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: model.onAppear)
    .onDisappear {
      preferences.maxDownloadStorageGB = maxStorageGB
      preferences.removeAfterUnused = removeAfter
    }
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
  private func chip(text: String) -> some View {
    Text(text)
      .font(.caption)
      .fontWeight(.semibold)
      .foregroundStyle(.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        Capsule().fill(Color.gray.opacity(0.15))
      )
  }
}

private struct StorageBreakdownCard: View {
  @ObservedObject var model: StoragePreferencesView.Model

  private var segments: [(color: Color, value: Int64)] {
    [
      (.orange, model.audiobooksBytes),
      (.blue, model.ebooksBytes),
      (.purple, model.imageCacheBytes),
    ]
  }

  private var totalDisplay: String {
    let bytes = Double(model.totalBytes)
    if bytes >= 1_000_000_000 {
      return String(format: "%.2f", bytes / 1_000_000_000)
    }
    if bytes >= 1_000_000 {
      return String(format: "%.0f", bytes / 1_000_000)
    }
    return "0"
  }

  private var totalUnit: String {
    let bytes = Double(model.totalBytes)
    if bytes >= 1_000_000_000 { return "GB used" }
    if bytes >= 1_000_000 { return "MB used" }
    return "GB used"
  }

  var body: some View {
    HStack(spacing: 16) {
      DonutChart(segments: segments, total: max(model.totalBytes, 1))
        .frame(width: 110, height: 110)
        .overlay {
          VStack(spacing: 0) {
            Text(verbatim: totalDisplay)
              .font(.system(size: 22, weight: .bold))
            Text(verbatim: totalUnit)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }

      VStack(alignment: .leading, spacing: 12) {
        legendRow(
          color: .orange,
          title: "Audiobooks",
          subtitle: bookCountText(model.audiobooksCount),
          size: formatBytes(model.audiobooksBytes)
        )
        legendRow(
          color: .blue,
          title: "Ebooks",
          subtitle: bookCountText(model.ebooksCount),
          size: formatBytes(model.ebooksBytes)
        )
        legendRow(color: .purple, title: "Image Cache", subtitle: "—", size: formatBytes(model.imageCacheBytes))
      }
    }
    .padding(16)
  }

  @ViewBuilder
  private func legendRow(color: Color, title: LocalizedStringKey, subtitle: String, size: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      RoundedRectangle(cornerRadius: 2)
        .fill(color)
        .frame(width: 8, height: 8)
        .padding(.top, 6)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.semibold)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Text(size)
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
    }
  }

  private func bookCountText(_ count: Int) -> String {
    count == 1 ? String(localized: "1 book") : String(localized: "\(count) books")
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let value = Double(bytes)
    if value >= 1_000_000_000 { return String(format: "%.1f GB", value / 1_000_000_000) }
    if value >= 1_000_000 { return String(format: "%.1f MB", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.0f KB", value / 1_000) }
    return "\(bytes) B"
  }
}

private struct DonutChart: View {
  let segments: [(color: Color, value: Int64)]
  let total: Int64

  private let lineWidth: CGFloat = 14

  private var arcs: [(color: Color, start: Double, end: Double)] {
    let totalDouble = Double(total)
    var cursor: Double = 0
    var result: [(color: Color, start: Double, end: Double)] = []
    for segment in segments where segment.value > 0 {
      let fraction = Double(segment.value) / totalDouble
      result.append((segment.color, cursor, cursor + fraction))
      cursor += fraction
    }
    return result
  }

  var body: some View {
    ZStack {
      Circle()
        .stroke(Color.gray.opacity(0.15), lineWidth: lineWidth)

      ForEach(0..<arcs.count, id: \.self) { i in
        Circle()
          .trim(from: arcs[i].start, to: arcs[i].end)
          .stroke(arcs[i].color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
          .rotationEffect(.degrees(-90))
      }
    }
    .padding(lineWidth / 2)
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
    var audiobooksBytes: Int64 = 0
    var audiobooksCount: Int = 0
    var ebooksBytes: Int64 = 0
    var ebooksCount: Int = 0
    var imageCacheBytes: Int64 = 0
    var totalBytes: Int64 = 0
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
      audiobooksBytes: Int64 = 0,
      audiobooksCount: Int = 0,
      ebooksBytes: Int64 = 0,
      ebooksCount: Int = 0,
      imageCacheBytes: Int64 = 0,
      totalBytes: Int64 = 0,
      serverDownloads: [ServerDownloads] = []
    ) {
      self.isLoading = isLoading
      self.totalSize = totalSize
      self.downloadSize = downloadSize
      self.cacheSize = cacheSize
      self.audiobooksBytes = audiobooksBytes
      self.audiobooksCount = audiobooksCount
      self.ebooksBytes = ebooksBytes
      self.ebooksCount = ebooksCount
      self.imageCacheBytes = imageCacheBytes
      self.totalBytes = totalBytes
      self.serverDownloads = serverDownloads
    }
  }
}

extension StoragePreferencesView.Model {
  static var mock = StoragePreferencesView.Model(
    isLoading: false,
    totalSize: "2.41 GB",
    downloadSize: "2.4 GB",
    cacheSize: "9.3 MB",
    audiobooksBytes: 1_600_000_000,
    audiobooksCount: 6,
    ebooksBytes: 800_000_000,
    ebooksCount: 3,
    imageCacheBytes: 9_300_000,
    totalBytes: 2_410_000_000
  )
}

private struct DownloadedBooksView: View {
  @Environment(\.appTheme) var theme
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
            .listRowBackground(theme.colors.background.card)
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
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle("Downloaded Books")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    StoragePreferencesView(model: .mock)
  }
}
