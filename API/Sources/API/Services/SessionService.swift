import Foundation
import UIKit

public final class SessionService {
  private let audiobookshelf: Audiobookshelf

  public enum SessionType {
    case player
    case watch

    var deviceID: String {
      switch self {
      case .player: SessionService.deviceID
      case .watch: SessionService.deviceID + "-watch"
      }
    }

    var clientName: String {
      switch self {
      case .player: "AudioBooth iOS"
      case .watch: "AudioBooth Watch"
      }
    }

    var mediaPlayer: String {
      switch self {
      case .player: "ios"
      case .watch: "watchos"
      }
    }
  }

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public static var deviceID: String {
    guard let deviceID = UserDefaults.standard.string(forKey: "deviceID") else {
      let deviceID = UUID().uuidString
      UserDefaults.standard.set(deviceID, forKey: "deviceID")
      return deviceID
    }
    return deviceID
  }

  public func start(
    itemID: String,
    episodeID: String? = nil,
    forceTranscode: Bool = false,
    sessionType: SessionType = .player,
    timeout: TimeInterval
  ) async throws -> PlaySession {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    struct PlayRequest: Codable {
      let forceDirectPlay: Bool
      let forceTranscode: Bool
      let supportedMimeTypes: [String]
      let mediaPlayer: String
      let deviceInfo: DeviceInfo

      struct DeviceInfo: Codable {
        let clientName: String
        let clientVersion: String?
        let deviceId: String
      }

      init(forceDirectPlay: Bool, forceTranscode: Bool, sessionType: SessionType) {
        self.forceDirectPlay = forceDirectPlay
        self.forceTranscode = forceTranscode
        self.supportedMimeTypes = [
          "audio/flac", "audio/mpeg", "audio/mp4", "audio/ogg", "audio/aac", "audio/x-aiff",
          "audio/webm",
        ]
        self.mediaPlayer = sessionType.mediaPlayer

        var clientVersion: String?
        if let infoDictionary = Bundle.main.infoDictionary,
          let version = infoDictionary["CFBundleShortVersionString"] as? String,
          let build = infoDictionary["CFBundleVersion"] as? String
        {
          clientVersion = "\(version) (\(build))"
        }

        self.deviceInfo = DeviceInfo(
          clientName: sessionType.clientName,
          clientVersion: clientVersion,
          deviceId: sessionType.deviceID
        )
      }
    }

    var path = "/api/items/\(itemID)/play"
    if let episodeID {
      path += "/\(episodeID)"
    }

    let request = NetworkRequest<PlaySession>(
      path: path,
      method: .post,
      body: PlayRequest(
        forceDirectPlay: !forceTranscode,
        forceTranscode: forceTranscode,
        sessionType: sessionType
      ),
      timeout: timeout
    )

    do {
      let response = try await networkService.send(request)
      return response.value
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to start play session: \(error.localizedDescription)"
      )
    }
  }

  public func sync(_ id: String, timeListened: Double, currentTime: Double) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    struct SyncRequest: Codable {
      let timeListened: Int
      let currentTime: Double
    }

    let timeout: TimeInterval
    #if os(watchOS)
    timeout = 20
    #else
    timeout = 10
    #endif

    let request = NetworkRequest<Data>(
      path: "/api/session/\(id)/sync",
      method: .post,
      body: SyncRequest(timeListened: Int(timeListened), currentTime: currentTime),
      timeout: timeout,
      discretionary: true
    )

    do {
      _ = try await networkService.send(request)
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to sync session: \(error.localizedDescription)"
      )
    }
  }

  public func close(_ id: String) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let request = NetworkRequest<Data>(
      path: "/api/session/\(id)/close",
      method: .post
    )

    do {
      _ = try await networkService.send(request)
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to close play session: \(error.localizedDescription)"
      )
    }
  }

  public func removeFromContinueListening(_ progressID: String) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    struct Response: Codable {}

    let request = NetworkRequest<Response>(
      path: "/api/me/progress/\(progressID)/remove-from-continue-listening",
      method: .get
    )

    do {
      _ = try await networkService.send(request)
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to remove from continue listening: \(error.localizedDescription)"
      )
    }
  }

  public func syncLocalSession(_ session: SessionSync) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    let request = NetworkRequest<Data>(
      path: "/api/session/local",
      method: .post,
      body: session,
      discretionary: true
    )

    do {
      _ = try await networkService.send(request)
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to sync local session: \(error.localizedDescription)"
      )
    }
  }

  public func syncLocalSessions(_ sessions: [SessionSync]) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    struct BulkSyncRequest: Codable {
      let sessions: [SessionSync]
      let deviceInfo: SessionSync.DeviceInfo
    }

    guard let firstSession = sessions.first else { return }

    let bulkRequest = BulkSyncRequest(
      sessions: sessions,
      deviceInfo: firstSession.deviceInfo
    )

    let request = NetworkRequest<Data>(
      path: "/api/session/local-all",
      method: .post,
      body: bulkRequest,
      discretionary: true
    )

    do {
      _ = try await networkService.send(request)
      print("syncLocalSessions successful!")
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to sync local sessions: \(error.localizedDescription)"
      )
    }
  }

  public struct ListeningSessionsResponse: Sendable {
    public let sessions: [SessionSync]
    public let total: Int
    public let numPages: Int
    public let page: Int
  }

  public func getListeningSessions(
    itemID: String,
    limit: Int? = nil,
    page: Int? = nil
  ) async throws -> ListeningSessionsResponse {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    struct Response: Codable {
      let total: Int
      let numPages: Int
      let page: Int
      let itemsPerPage: Int
      let sessions: [SessionSync]
    }

    var query: [String: String] = [:]
    if let limit {
      query["itemsPerPage"] = String(limit)
    }
    if let page {
      query["page"] = String(page)
    }

    let request = NetworkRequest<Response>(
      path: "/api/me/item/listening-sessions/\(itemID)",
      method: .get,
      query: query
    )

    do {
      let response = try await networkService.send(request)
      return ListeningSessionsResponse(
        sessions: response.value.sessions,
        total: response.value.total,
        numPages: response.value.numPages,
        page: response.value.page
      )
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to fetch listening sessions: \(error.localizedDescription)"
      )
    }
  }
}
