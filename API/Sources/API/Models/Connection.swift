import Foundation

public struct Connection: Codable, Sendable {
  public let id: String
  public let serverURL: URL
  public let token: Credentials
  public let customHeaders: [String: String]
  public let alias: String?

  public init(
    id: String? = nil,
    serverURL: URL,
    token: Credentials,
    customHeaders: [String: String] = [:],
    alias: String? = nil
  ) {
    self.id = id ?? UUID().uuidString
    self.serverURL = serverURL
    self.token = token
    self.customHeaders = customHeaders
    self.alias = alias
  }

  public init(_ server: Server) {
    self.init(
      id: server.id,
      serverURL: server.baseURL,
      token: server.token,
      customHeaders: server.customHeaders,
      alias: server.alias
    )
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    serverURL = try container.decode(URL.self, forKey: .serverURL)
    if let legacy = try? container.decode(String.self, forKey: .token) {
      token = .legacy(token: legacy)
    } else {
      token = try container.decode(Credentials.self, forKey: .token)
    }
    customHeaders = try container.decode([String: String].self, forKey: .customHeaders)
    alias = try container.decodeIfPresent(String.self, forKey: .alias)
  }
}

public enum Credentials: Codable, Sendable {
  case legacy(token: String)
  case bearer(accessToken: String, refreshToken: String, expiresAt: TimeInterval)

  public var bearer: String {
    switch self {
    case .legacy(let token):
      return "Bearer \(token)"
    case .bearer(let accessToken, _, _):
      return "Bearer \(accessToken)"
    }
  }
}

public struct JWT {
  public let userID: String?
  public let exp: TimeInterval?
  public let username: String?

  public init?(_ token: String) {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }

    let payload = String(parts[1])
    var base64 =
      payload
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")

    let paddingLength = (4 - base64.count % 4) % 4
    base64 += String(repeating: "=", count: paddingLength)

    guard let data = Data(base64Encoded: base64),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    self.userID = json["userId"] as? String
    self.username = json["username"] as? String
    self.exp = json["exp"] as? TimeInterval
  }
}
