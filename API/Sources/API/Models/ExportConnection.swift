import Foundation

public struct ExportConnection: Codable, Sendable, Equatable {
  public let url: URL
  public let token: String?
  public let headers: [String: String]
  public let alias: String?
  public let alternativeURL: URL?
  public let isUsingAlternativeURL: Bool?

  public init?(_ connection: Connection, includeToken: Bool = false) {
    url =
      connection.isUsingAlternativeURL
      ? connection.alternativeURL ?? connection.serverURL
      : connection.serverURL
    headers = connection.customHeaders
    alias = connection.alias
    alternativeURL = connection.alternativeURL
    isUsingAlternativeURL = connection.isUsingAlternativeURL

    if includeToken {
      switch connection.token {
      case .bearer(_, let refreshToken, _):
        token = refreshToken
      case .apiKey(let key):
        token = key
      case .legacy:
        return nil
      }
    } else {
      token = nil
    }
  }
}
