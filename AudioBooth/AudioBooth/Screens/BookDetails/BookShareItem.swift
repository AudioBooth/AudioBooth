import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct BookShareItem: Transferable, Identifiable {
  enum Content {
    case audiobook([URL])
    case ebook(URL)
  }

  let content: Content
  let name: String

  var id: String { String(describing: label) }

  var label: LocalizedStringKey {
    switch content {
    case .audiobook: "Audiobook"
    case .ebook: "Ebook"
    }
  }

  var icon: String {
    switch content {
    case .audiobook: "headphones"
    case .ebook: "book.closed"
    }
  }

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .data) { item in
      SentTransferredFile(try await item.resolve())
    }
  }

  private func resolve() async throws -> URL {
    switch content {
    case .audiobook(let trackURLs):
      guard let url = prepareAudiobook(trackURLs) else {
        throw CocoaError(.fileWriteUnknown)
      }
      return url

    case .ebook(let url):
      let sanitized = Self.sanitizedName(name)
      let filename = sanitized.isEmpty ? "ebook" : sanitized

      if url.isFileURL {
        return Self.prepared(linkingTo: url, named: filename)
      }
      return try await downloadEbook(from: url, named: filename)
    }
  }

  private func prepareAudiobook(_ trackURLs: [URL]) -> URL? {
    let title = Self.sanitizedName(name)
    guard !title.isEmpty, !trackURLs.isEmpty else { return nil }

    if trackURLs.count == 1, let source = trackURLs.first {
      let ext = source.pathExtension
      return Self.prepared(linkingTo: source, named: ext.isEmpty ? title : "\(title).\(ext)")
    }

    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent("ShareAudio", isDirectory: true)
    try? fm.removeItem(at: directory)
    try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

    let folder = directory.appendingPathComponent(title, isDirectory: true)
    do {
      try fm.createDirectory(at: folder, withIntermediateDirectories: true)
      for (index, source) in trackURLs.enumerated() {
        let ext = source.pathExtension.isEmpty ? "mp3" : source.pathExtension
        let trackName = String(format: "%03d.%@", index + 1, ext)
        try fm.copyItem(at: source, to: folder.appendingPathComponent(trackName))
      }
    } catch {
      return nil
    }

    let zipDestination = directory.appendingPathComponent("\(title).zip")
    guard Self.zip(directory: folder, to: zipDestination) else { return nil }
    return zipDestination
  }

  private func downloadEbook(from remoteURL: URL, named filename: String) async throws -> URL {
    let (downloadedURL, _) = try await URLSession.shared.download(from: remoteURL)

    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent("ShareEbook", isDirectory: true)
    try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

    let destination = directory.appendingPathComponent(filename)
    try? fm.removeItem(at: destination)
    try fm.moveItem(at: downloadedURL, to: destination)

    return destination
  }

  private static func zip(directory: URL, to destination: URL) -> Bool {
    let coordinator = NSFileCoordinator()
    var coordinationError: NSError?
    var didSucceed = false

    coordinator.coordinate(
      readingItemAt: directory,
      options: [.forUploading],
      error: &coordinationError
    ) { zippedURL in
      try? FileManager.default.removeItem(at: destination)
      didSucceed = (try? FileManager.default.copyItem(at: zippedURL, to: destination)) != nil
    }

    return didSucceed && coordinationError == nil
  }

  private static func sanitizedName(_ title: String) -> String {
    title
      .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
      .joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func prepared(linkingTo source: URL, named name: String) -> URL {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory
      .appendingPathComponent("Share", isDirectory: true)
      .appendingPathComponent(source.lastPathComponent, isDirectory: true)
    let destination = directory.appendingPathComponent(name)

    if fm.fileExists(atPath: destination.path) {
      return destination
    }

    try? fm.removeItem(at: directory)
    try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

    if (try? fm.linkItem(at: source, to: destination)) != nil {
      return destination
    }
    if (try? fm.copyItem(at: source, to: destination)) != nil {
      return destination
    }
    return source
  }
}
