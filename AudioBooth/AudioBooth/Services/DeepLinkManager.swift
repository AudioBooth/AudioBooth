import API
import Combine
import Foundation
import SwiftUI

class DeepLinkManager: ObservableObject {
  static let shared = DeepLinkManager()

  @Published var pendingExportConnection: ExportConnection?

  private init() {}

  func handleDeepLink(_ url: URL) {
    guard
      ["audiobooth", "audiobs"].contains(url.scheme),
      let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
    else { return }

    switch components.host {
    case "play":
      handlePlayDeepLink(components)
    case "open":
      handleOpenDeepLink(components)
    case "connection":
      handleConnectionDeepLink(url)
    default:
      break
    }
  }

  private func handlePlayDeepLink(_ components: URLComponents) {
    let bookID = String(components.path.dropFirst())
    let playerManager = PlayerManager.shared

    Task {
      await playerManager.play(bookID)
    }
  }

  private func handleOpenDeepLink(_ components: URLComponents) {
    let bookID = String(components.path.dropFirst())
    let playerManager = PlayerManager.shared

    Task {
      await playerManager.open(bookID)
    }
  }

  private func handleConnectionDeepLink(_ url: URL) {
    guard let exportConnection = Self.decodeConnectionDeepLink(url) else {
      Toast(error: "Invalid connection link").show()
      return
    }

    Toast(message: "Testing shared connection...").show()
    Task {
      await validateAndImportConnection(exportConnection)
    }
  }

  @MainActor
  private func validateAndImportConnection(_ exportConnection: ExportConnection) async {
    do {
      _ = try await Audiobookshelf.shared.networkDiscovery.fetchServerStatus(
        serverURL: exportConnection.url,
        headers: exportConnection.headers
      )
    } catch {
      Toast(error: "Could not reach server with the shared URL and headers: \(error.localizedDescription)").show()
      return
    }

    if let token = exportConnection.token {
      let credentials: Credentials
      if JWT(token)?.type == .api {
        do {
          let response = try await Audiobookshelf.shared.authentication.validateAPIKeyConnection(
            serverURL: exportConnection.url.absoluteString,
            apiKey: token,
            customHeaders: exportConnection.headers
          )
          let connection = Connection(
            serverURL: response.serverURL,
            token: .apiKey(key: token),
            customHeaders: exportConnection.headers,
            alias: exportConnection.alias,
            alternativeURL: exportConnection.alternativeURL,
            isUsingAlternativeURL: exportConnection.isUsingAlternativeURL ?? false
          )
          Audiobookshelf.shared.authentication.restoreConnection(connection)
          Audiobookshelf.shared.authentication.server?.update(with: response.authorize)
          Toast(success: "Connection imported successfully").show()
        } catch {
          Toast(error: "Server reachable, but Audiobookshelf credentials failed: \(error.localizedDescription)").show()
        }
        return
      } else {
        credentials = .bearer(accessToken: "", refreshToken: token, expiresAt: 0)
      }
      let connection = Connection(
        serverURL: exportConnection.url,
        token: credentials,
        customHeaders: exportConnection.headers,
        alias: exportConnection.alias,
        alternativeURL: exportConnection.alternativeURL,
        isUsingAlternativeURL: exportConnection.isUsingAlternativeURL ?? false
      )
      Audiobookshelf.shared.authentication.restoreConnection(connection)
      Toast(success: "Connection imported. Audiobookshelf credentials will be verified on first use.").show()
    } else {
      pendingExportConnection = exportConnection
      Toast(success: "Server reachable. Sign in to finish importing this connection.").show()
    }
  }

  static func createConnectionDeepLink(from connection: Connection, includeToken: Bool = false) -> URL? {
    let encoder = JSONEncoder()
    guard
      let connection = ExportConnection(connection, includeToken: includeToken),
      let data = try? encoder.encode(connection),
      let base64 = data.base64EncodedString()
        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    else {
      return nil
    }

    return URL(string: "audiobooth://connection/\(base64)")
  }

  static func decodeConnectionDeepLink(_ url: URL) -> ExportConnection? {
    guard url.scheme == "audiobooth" || url.scheme == "audiobs",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
      components.host == "connection",
      let data = Data(base64Encoded: String(components.path.dropFirst()))
    else {
      return nil
    }

    return try? JSONDecoder().decode(ExportConnection.self, from: data)
  }
}

extension DeepLinkManager {
  typealias ExportConnection = API.ExportConnection
}

struct DeepLinkHandlerModifier: ViewModifier {
  @ObservedObject private var deepLinkManager = DeepLinkManager.shared
  @State private var showingDeepLinkServer = false
  @State private var pendingExportConnection: DeepLinkManager.ExportConnection?

  func body(content: Content) -> some View {
    content
      .onOpenURL { url in
        DeepLinkManager.shared.handleDeepLink(url)
      }
      .sheet(isPresented: $showingDeepLinkServer) {
        ServerListPage(model: ServerListModel(pendingExportConnection: pendingExportConnection))
      }
      .onChange(of: deepLinkManager.pendingExportConnection) { _, newValue in
        if let exportConnection = newValue {
          pendingExportConnection = exportConnection
          showingDeepLinkServer = true
          deepLinkManager.pendingExportConnection = nil
        }
      }
  }
}

extension View {
  func handleDeepLinks() -> some View {
    modifier(DeepLinkHandlerModifier())
  }
}
