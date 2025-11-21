import Foundation
import UIKit

public final class SessionService {
  private let audiobookshelf: Audiobookshelf

  public enum SessionType {
    case player
    case download
    case watch

    var deviceID: String {
      switch self {
      case .player: SessionService.deviceID
      case .download: SessionService.deviceID + "-download"
      case .watch: SessionService.deviceID + "-watch"
      }
    }

    var clientName: String {
      switch self {
      case .player, .download: "AudioBooth iOS"
      case .watch: "AudioBooth Watch"
      }
    }

    var mediaPlayer: String {
      switch self {
      case .player, .download: "ios"
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
    forceDirectPlay: Bool = false,
    forceTranscode: Bool = false,
    sessionType: SessionType = .player
  ) async throws -> PlaySession {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first.")
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

    let request = NetworkRequest<PlaySession>(
      path: "/api/items/\(itemID)/play",
      method: .post,
      body: PlayRequest(
        forceDirectPlay: forceDirectPlay, forceTranscode: forceTranscode, sessionType: sessionType),
      timeout: 5
    )

    do {
      let response = try await networkService.send(request)
      return response.value
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to start play session: \(error.localizedDescription)")
    }
  }

  public func sync(_ id: String, timeListened: Double, currentTime: Double) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first.")
    }

    struct SyncRequest: Codable {
      let timeListened: Int
      let currentTime: Double
    }

    let timeout: TimeInterval
    #if os(watchOS)
      timeout = 15
    #else
      timeout = 5
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
        "Failed to sync session: \(error.localizedDescription)")
    }
  }

  public func close(_ id: String) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first.")
    }

    let request = NetworkRequest<Data>(
      path: "/api/session/\(id)/close",
      method: .post
    )

    do {
      _ = try await networkService.send(request)
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Failed to close play session: \(error.localizedDescription)")
    }
  }

  public func removeFromContinueListening(_ progressID: String) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first.")
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
        "Failed to remove from continue listening: \(error.localizedDescription)")
    }
  }

  public func syncLocalSession(_ session: SessionSync) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first.")
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
        "Failed to sync local session: \(error.localizedDescription)")
    }
  }

  public func syncLocalSessions(_ sessions: [SessionSync]) async throws {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first.")
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
        "Failed to sync local sessions: \(error.localizedDescription)")
    }
  }
}
