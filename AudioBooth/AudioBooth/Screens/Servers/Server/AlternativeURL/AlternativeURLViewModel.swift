import API
import Foundation

final class AlternativeURLViewModel: AlternativeURLView.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let server: Server

  init(server: Server) {
    self.server = server
    super.init(url: server.alternativeURL?.absoluteString ?? "")
  }

  override func onSaveURL() {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parsedURL = URL(string: trimmed), parsedURL.scheme == "http" || parsedURL.scheme == "https" else {
      error = "Invalid URL"
      return
    }

    Task {
      isValidating = true
      defer { isValidating = false }

      do {
        try await audiobookshelf.authentication.verifyAlternativeURL(parsedURL, for: server.id)
        audiobookshelf.authentication.updateAlternativeURL(server.id, url: parsedURL)
        savedURL = trimmed
        error = nil
        Toast(success: "Alternative URL saved").show()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  override func onClearURL() {
    if !savedURL.isEmpty {
      audiobookshelf.authentication.updateAlternativeURL(server.id, url: nil)
      if server.isUsingAlternativeURL {
        audiobookshelf.authentication.setUsingAlternativeURL(server.id, isUsing: false)
      }
      Toast(success: "Alternative URL removed").show()
    }
    url = ""
    savedURL = ""
    error = nil
  }
}
