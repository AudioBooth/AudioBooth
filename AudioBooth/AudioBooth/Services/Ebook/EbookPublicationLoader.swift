import Foundation
import ReadiumShared
import ReadiumStreamer

final class EbookPublicationLoader {
  enum LoaderError: LocalizedError {
    case unsupportedURL

    var errorDescription: String? {
      switch self {
      case .unsupportedURL:
        String(localized: "This ebook's location can't be opened.")
      }
    }
  }

  private lazy var assetRetriever = AssetRetriever(
    httpClient: DefaultHTTPClient()
  )

  private lazy var publicationOpener = PublicationOpener(
    parser: DefaultPublicationParser(
      httpClient: DefaultHTTPClient(),
      assetRetriever: assetRetriever,
      pdfFactory: DefaultPDFDocumentFactory()
    )
  )

  func open(at localURL: URL) async throws -> Publication {
    guard let fileURL = FileURL(url: localURL) else { throw LoaderError.unsupportedURL }

    let asset = try await assetRetriever.retrieve(url: fileURL).get()
    return try await publicationOpener.open(asset: asset, allowUserInteraction: false).get()
  }
}
