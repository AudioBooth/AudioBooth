import API
import Foundation
import Logging
import Models
import ReadiumShared
import ReadiumStreamer

/// Finds the ebook for an audiobook, fetches it and builds its text index. Indexes are cached
/// for the app session so repeated syncs of the same title are instant.

final class EbookIndexLoader {
  enum LoaderError: LocalizedError {
    case ebookUnavailable
    case ebookHasNoText

    var errorDescription: String? {
      switch self {
      case .ebookUnavailable:
        String(
          localized:
            "No ebook was found for this book in your library. Page Sync needs the ebook text to locate the page."
        )
      case .ebookHasNoText:
        String(localized: "The ebook text could not be read.")
      }
    }
  }

  struct Loaded {
    let index: EbookTextIndex
    let ebookBook: Book
  }

  private static var cache: [String: Loaded] = [:]
  private static var temporaryFiles: [String: URL] = [:]

  private let assetRetriever = AssetRetriever(httpClient: DefaultHTTPClient())
  private lazy var publicationOpener = PublicationOpener(
    parser: DefaultPublicationParser(
      httpClient: DefaultHTTPClient(),
      assetRetriever: assetRetriever,
      pdfFactory: DefaultPDFDocumentFactory()
    )
  )

  func load(for book: Book) async throws -> Loaded {
    if let cached = Self.cache[book.id] {
      return cached
    }

    guard let ebookBook = try await LibraryItemPairing.ebookItem(for: book) else {
      throw LoaderError.ebookUnavailable
    }

    let fileURL = try await ebookFileURL(for: ebookBook)
    guard let readiumURL = FileURL(url: fileURL) else { throw LoaderError.ebookUnavailable }

    let asset = try await assetRetriever.retrieve(url: readiumURL).get()
    let publication = try await publicationOpener.open(asset: asset, allowUserInteraction: false).get()
    let index = try await Self.index(for: publication)

    let loaded = Loaded(index: index, ebookBook: ebookBook)
    Self.cache[book.id] = loaded
    return loaded
  }

  /// Builds (or returns the cached) index for a publication that is already open, such as the
  /// one shown by the ebook reader.
  static func index(for publication: Publication, cacheKey: String? = nil) async throws -> EbookTextIndex {
    if let cacheKey, let cached = cache[cacheKey] {
      return cached.index
    }
    let index = await Task.detached {
      await EbookTextIndex.build(from: publication)
    }.value
    guard !index.isEmpty else { throw LoaderError.ebookHasNoText }
    AppLogger.viewModel.info("Page Sync: indexed \(index.sections.count) sections, \(index.totalLength) characters")
    return index
  }

  private func ebookFileURL(for ebookBook: Book) async throws -> URL {
    if let localURL = (try? LocalBook.fetch(bookID: ebookBook.id))?.ebookLocalPath {
      return localURL
    }
    if let temporary = Self.temporaryFiles[ebookBook.id], FileManager.default.fileExists(atPath: temporary.path) {
      return temporary
    }

    guard let ebookURL = ebookBook.ebookURL,
      let server = Audiobookshelf.shared.authentication.server
    else { throw LoaderError.ebookUnavailable }

    var request = URLRequest(url: ebookURL)
    request.setValue(server.token.bearer, forHTTPHeaderField: "Authorization")
    for (field, value) in server.customHeaders {
      request.setValue(value, forHTTPHeaderField: field)
    }

    let (downloadedURL, response) = try await URLSession.shared.download(for: request)
    if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
      try? FileManager.default.removeItem(at: downloadedURL)
      throw LoaderError.ebookUnavailable
    }

    var fileExtension = ebookBook.media.ebookFile?.metadata.ext ?? ebookBook.media.ebookFormat ?? "epub"
    while fileExtension.hasPrefix(".") {
      fileExtension.removeFirst()
    }

    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("page-sync-\(ebookBook.id)")
      .appendingPathExtension(fileExtension)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: downloadedURL, to: destination)

    Self.temporaryFiles[ebookBook.id] = destination
    return destination
  }
}
