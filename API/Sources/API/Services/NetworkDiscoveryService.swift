import Foundation
import Network

public final class NetworkDiscoveryService: @unchecked Sendable {
  private let audiobookshelf: Audiobookshelf
  private let defaultPort = 13378
  private let timeout: TimeInterval = 3.0

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public func fetchServerStatus(serverURL: URL) async throws -> ServerStatus {
    let client = NetworkService(baseURL: serverURL)

    let request = NetworkRequest<ServerStatus>(
      path: "/status",
      method: .get,
      timeout: self.timeout
    )

    let response = try await client.send(request)
    return response.value
  }

  public func discoverServers(port: Int? = nil) async -> [DiscoveredServer] {
    let discoveryPort = port ?? defaultPort
    let networkRanges = await getNetworkRanges()
    var discoveredServers: [DiscoveredServer] = []

    await withTaskGroup(of: DiscoveredServer?.self) { group in
      for range in networkRanges {
        for ip in range {
          group.addTask {
            await self.testServer(ip: ip, port: discoveryPort)
          }
        }
      }

      for await server in group {
        if let server {
          discoveredServers.append(server)
        }
      }
    }

    return discoveredServers.sorted { $0.responseTime < $1.responseTime }
  }

  private func getNetworkRanges() async -> [[String]] {
    let ranges: [[String]] = [
      generateIPRange(base: "192.168.1", start: 1, end: 254),
      generateIPRange(base: "192.168.0", start: 1, end: 254),
      generateIPRange(base: "10.0.0", start: 1, end: 254),
      generateIPRange(base: "10.0.1", start: 1, end: 254),
      ["127.0.0.1"],
    ]
    return ranges
  }

  private func generateIPRange(base: String, start: Int, end: Int) -> [String] {
    return (start...end).map { "\(base).\($0)" }
  }

  private func testServer(ip: String, port: Int) async -> DiscoveredServer? {
    let startTime = Date()

    guard let serverURL = URL(string: "http://\(ip):\(port)") else {
      return nil
    }

    let testClient = NetworkService(baseURL: serverURL)

    struct StatusResponse: Codable {
      let app: String?
      let serverVersion: String?
      let isInit: Bool?
      let authMethods: [String]?
      let authFormData: AuthFormData?

      struct AuthFormData: Codable {
        let authLoginCustomMessage: String?
        let authOpenIDButtonText: String?
        let authOpenIDAutoLaunch: Bool?
      }
    }

    do {
      let request = NetworkRequest<StatusResponse>(
        path: "/status",
        method: .get,
        timeout: self.timeout
      )

      let response = try await testClient.send(request)
      let responseTime = Date().timeIntervalSince(startTime)

      let isAudiobookshelf = response.value.app?.contains("audiobookshelf") ?? false

      if isAudiobookshelf {
        let serverInfo = DiscoveredServer.ServerInfo(
          version: response.value.serverVersion,
          name: ip
        )

        return DiscoveredServer(
          serverURL: serverURL,
          responseTime: responseTime,
          serverInfo: serverInfo
        )
      }
    } catch {
      return nil
    }

    return nil
  }
}
