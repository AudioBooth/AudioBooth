import API
import Foundation

public struct Session {
  public let id: String
  public let url: URL

  @MainActor
  public init?(from playSession: PlaySession) {
    guard let serverURL = Audiobookshelf.shared.serverURL else {
      return nil
    }

    let baseURL = serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let url = URL(string: "\(baseURL)/public/session/\(playSession.id)") else {
      return nil
    }

    self.id = playSession.id
    self.url = url
  }
}
