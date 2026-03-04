import API
import SafariServices
import UIKit

final class EbooksContentModel: EbooksContent.Model {
  private let bookID: String

  init(
    ebooks: [EbooksContent.SupplementaryEbook],
    bookID: String
  ) {
    self.bookID = bookID
    super.init(ebooks: ebooks)
  }

  override func onEbookTapped(_ ebook: EbooksContent.SupplementaryEbook) {
    guard let url = ebook.url(for: bookID) else {
      Toast(error: "Unable to open ebook").show()
      return
    }

    ebookReader = EbookReaderViewModel(source: .remote(url), bookID: nil)
  }

  override func onOpenOnWebTapped(_ ebook: EbooksContent.SupplementaryEbook) {
    guard let url = ebook.url(for: bookID) else {
      Toast(error: "Unable to open ebook").show()
      return
    }

    openInSafari(url)
  }

  private func openInSafari(_ url: URL) {
    let safariViewController = SFSafariViewController(url: url)
    safariViewController.modalPresentationStyle = .overFullScreen

    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = windowScene.windows.first,
      let rootViewController = window.rootViewController
    {
      rootViewController.present(safariViewController, animated: true)
    }
  }
}

extension EbooksContent.SupplementaryEbook {
  func url(for bookID: String) -> URL? {
    guard let serverURL = Audiobookshelf.shared.serverURL,
      let token = Audiobookshelf.shared.authentication.server?.token
    else {
      return nil
    }

    var url = serverURL.appendingPathComponent("api/items/\(bookID)/file/\(ino)")
    switch token {
    case .legacy(let token):
      url.append(queryItems: [URLQueryItem(name: "token", value: token)])
    case .bearer(let accessToken, _, _):
      url.append(queryItems: [URLQueryItem(name: "token", value: accessToken)])
    case .apiKey(let key):
      url.append(queryItems: [URLQueryItem(name: "token", value: key)])
    }

    return url
  }
}
