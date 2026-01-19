import API
import Combine
import Foundation
import Models
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

    if let token = exportConnection.token {
      let connection = Connection(
        serverURL: exportConnection.url,
        token: .bearer(accessToken: "", refreshToken: token, expiresAt: 0),
        customHeaders: exportConnection.headers
      )
      Audiobookshelf.shared.authentication.restoreConnection(connection)
      Toast(success: "Connection imported successfully").show()
    } else {
      pendingExportConnection = exportConnection
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
  public struct ExportConnection: Codable, Sendable, Equatable {
    public let url: URL
    public let token: String?
    public let headers: [String: String]

    init?(_ connection: Connection, includeToken: Bool = false) {
      url = connection.serverURL
      headers = connection.customHeaders

      if includeToken {
        guard case .bearer(_, let refreshToken, _) = connection.token else { return nil }
        token = refreshToken
      } else {
        token = nil
      }
    }
  }
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
