import Audiobookshelf
import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

final class OIDCAuthenticationManager: NSObject {
  private var serverURL: String
  private var pkce: PKCE
  private var session: ASWebAuthenticationSession?
  private var capturedCookies: [HTTPCookie] = []

  weak var delegate: OIDCAuthenticationDelegate?

  init(serverURL: String) {
    self.serverURL = serverURL
    self.pkce = PKCE()
    super.init()
  }

  func start() {
    Task {
      do {
        let authURL = try buildOIDCURL()

        let (redirectURL, cookies) = try await makeInitialOAuthRequest(authURL: authURL)
        self.capturedCookies = cookies

        self.openAuthenticationSession(with: redirectURL)
      } catch {
        delegate?.oidcAuthentication(didFailWithError: error)
      }
    }
  }

  private func openAuthenticationSession(with url: URL) {
    session = ASWebAuthenticationSession(
      url: url,
      callbackURLScheme: "audiobs"
    ) { [weak self] callbackURL, error in
      self?.handleAuthenticationResult(callbackURL: callbackURL, error: error)
    }

    session?.presentationContextProvider = self
    session?.start()
  }

  func cancel() {
    session?.cancel()
    session = nil
  }

  private func handleAuthenticationResult(callbackURL: URL?, error: Error?) {
    if let error = error {
      delegate?.oidcAuthentication(didFailWithError: error)
      return
    }

    guard let callbackURL = callbackURL else {
      delegate?.oidcAuthentication(didFailWithError: OIDCError.invalidCallback)
      return
    }

    guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems
    else {
      delegate?.oidcAuthentication(didFailWithError: OIDCError.invalidCallback)
      return
    }

    let code = queryItems.first { $0.name == "code" }?.value
    let state = queryItems.first { $0.name == "state" }?.value
    let error = queryItems.first { $0.name == "error" }?.value

    if let error = error {
      delegate?.oidcAuthentication(didFailWithError: OIDCError.authenticationFailed(error))
      return
    }

    guard let authCode = code else {
      let availableParams = queryItems.map { "\($0.name): \($0.value ?? "nil")" }.joined(
        separator: ", ")
      delegate?.oidcAuthentication(didFailWithError: OIDCError.noAuthorizationCode(availableParams))
      return
    }

    Task {
      do {

        try await Audiobookshelf.shared.authentication.loginWithOIDC(
          serverURL: serverURL,
          code: authCode,
          verifier: pkce.verifier,
          state: state,
          cookies: capturedCookies
        )

        delegate?.oidcAuthenticationDidSucceed()
      } catch {
        delegate?.oidcAuthentication(didFailWithError: error)
      }
    }
  }

  private func buildOIDCURL() throws -> URL {
    guard let baseURL = URL(string: serverURL) else {
      throw OIDCError.invalidServerURL
    }

    var components = URLComponents(
      url: baseURL.appendingPathComponent("/auth/openid"),
      resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
      URLQueryItem(name: "client_id", value: "AudioBS"),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: "openid"),
      URLQueryItem(name: "redirect_uri", value: "audiobs://oauth"),
      URLQueryItem(name: "code_challenge", value: pkce.challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]

    guard let authURL = components?.url else {
      throw OIDCError.failedToConstructURL
    }

    return authURL
  }

  private func makeInitialOAuthRequest(authURL: URL) async throws -> (URL, [HTTPCookie]) {
    var request = URLRequest(url: authURL)
    request.httpMethod = "GET"

    let config = URLSessionConfiguration.default
    let session = URLSession(
      configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    let cookies = HTTPCookie.cookies(
      withResponseHeaderFields: httpResponse.allHeaderFields as! [String: String], for: authURL)

    if httpResponse.statusCode == 302,
      let locationString = httpResponse.allHeaderFields["Location"] as? String
    {

      guard var redirectComponents = URLComponents(string: locationString) else {
        throw URLError(.badServerResponse)
      }

      // Update the redirect_uri parameter to use our custom scheme
      if var queryItems = redirectComponents.queryItems {
        for i in 0..<queryItems.count {
          if queryItems[i].name == "redirect_uri" {
            queryItems[i].value = "audiobs://oauth"
            break
          }
        }
        redirectComponents.queryItems = queryItems
      }

      guard let updatedRedirectURL = redirectComponents.url else {
        throw URLError(.badServerResponse)
      }

      if let components = URLComponents(url: updatedRedirectURL, resolvingAgainstBaseURL: false),
        let queryItems = components.queryItems,
        let code = queryItems.first(where: { $0.name == "code" })?.value
      {

        let state = queryItems.first(where: { $0.name == "state" })?.value
        self.handleDirectCallback(code: code, state: state)

        return (updatedRedirectURL, cookies)
      }

      return (updatedRedirectURL, cookies)
    }

    throw URLError(.badServerResponse)
  }

  private func handleDirectCallback(code: String, state: String?) {
    Task {
      do {

        try await Audiobookshelf.shared.authentication.loginWithOIDC(
          serverURL: serverURL,
          code: code,
          verifier: pkce.verifier,
          state: state,
          cookies: capturedCookies
        )

        delegate?.oidcAuthenticationDidSucceed()
      } catch {
        delegate?.oidcAuthentication(didFailWithError: error)
      }
    }
  }
}

extension OIDCAuthenticationManager: ASWebAuthenticationPresentationContextProviding {
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = windowScene.windows.first
    else {
      return ASPresentationAnchor()
    }
    return window
  }
}

extension OIDCAuthenticationManager {
  struct PKCE {
    let verifier: String
    let challenge: String

    init() {
      let array = (0..<42).map { _ in UInt32.random(in: 0...UInt32.max) }
      self.verifier = array.map { String(format: "%02x", $0) }.joined()

      let data = Data(verifier.utf8)
      let hash = SHA256.hash(data: data)
      self.challenge = Data(hash)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    }
  }
}

protocol OIDCAuthenticationDelegate: AnyObject {
  func oidcAuthenticationDidSucceed()
  func oidcAuthentication(didFailWithError error: Error)
}

enum OIDCError: LocalizedError {
  case invalidCallback
  case authenticationFailed(String)
  case noAuthorizationCode(String)
  case invalidServerURL
  case failedToConstructURL

  var errorDescription: String? {
    switch self {
    case .invalidCallback:
      return "Invalid callback URL"
    case .authenticationFailed(let error):
      return "Authentication failed: \(error)"
    case .noAuthorizationCode(let available):
      return "No authorization code found. Available parameters: \(available)"
    case .invalidServerURL:
      return "Invalid server URL"
    case .failedToConstructURL:
      return "Failed to construct authorization URL"
    }
  }
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
