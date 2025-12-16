import Foundation

public struct ServerStatus: Codable {
  public let app: String?
  public let serverVersion: String?
  public let authMethods: [String]?
  public let authFormData: AuthFormData?

  public struct AuthFormData: Codable {
    public let authLoginCustomMessage: String?
    public let authOpenIDButtonText: String?
    public let authOpenIDAutoLaunch: Bool?
  }

  public var supportsLocal: Bool {
    authMethods?.contains("local") ?? true
  }

  public var supportsOIDC: Bool {
    authMethods?.contains("openid") ?? false
  }

  public var shouldAutoLaunchOIDC: Bool {
    authFormData?.authOpenIDAutoLaunch ?? false
  }
}
