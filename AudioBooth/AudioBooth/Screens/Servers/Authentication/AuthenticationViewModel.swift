import API
import AuthenticationServices
import Foundation
import Logging
import SwiftUI

final class AuthenticationViewModel: AuthenticationView.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let server: Server

  init(server: Server) {
    self.server = server
    super.init(serverURL: server.baseURL)
  }

  override func onLoginTapped() {
    guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return
    }

    isLoading = true

    Task {
      do {
        _ = try await audiobookshelf.authentication.login(
          serverURL: server.baseURL.absoluteString,
          username: username.trimmingCharacters(in: .whitespacesAndNewlines),
          password: password,
          customHeaders: server.customHeaders,
          existingServerID: server.id
        )
        password = ""
        onAuthenticationSuccess()
        shouldDismiss = true
      } catch {
        AppLogger.viewModel.error("Re-authentication failed: \(error.localizedDescription)")
        Toast(error: error.localizedDescription).show()
      }

      isLoading = false
    }
  }

  override func onAPIKeyLoginTapped() {
    let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedKey.isEmpty else { return }

    isLoading = true

    Task {
      do {
        _ = try await audiobookshelf.authentication.loginWithAPIKey(
          serverURL: server.baseURL.absoluteString,
          apiKey: trimmedKey,
          customHeaders: server.customHeaders,
          existingServerID: server.id
        )
        apiKey = ""
        onAuthenticationSuccess()
        shouldDismiss = true
      } catch {
        AppLogger.viewModel.error("API key authentication failed: \(error.localizedDescription)")
        Toast(error: error.localizedDescription).show()
      }

      isLoading = false
    }
  }

  override func onOIDCLoginTapped(using session: WebAuthenticationSession) {
    isLoading = true

    let authManager = OIDCAuthenticationManager(
      serverURL: server.baseURL.absoluteString,
      customHeaders: server.customHeaders,
      existingServerID: server.id
    )

    Task {
      do {
        _ = try await authManager.start(using: session)
        isLoading = false
        Toast(success: "Successfully authenticated with SSO").show()
        onAuthenticationSuccess()
        shouldDismiss = true
      } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
        isLoading = false
      } catch {
        Toast(error: "SSO login failed: \(error.localizedDescription)").show()
        isLoading = false
      }
    }
  }
}
