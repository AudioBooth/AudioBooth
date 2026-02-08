import Foundation

public struct SessionSync: Codable, Sendable {
  public let id: String
  public let libraryItemId: String
  public let episodeId: String?
  public let mediaType: String
  public let duration: TimeInterval
  public let startTime: TimeInterval
  public let currentTime: TimeInterval
  public let timeListening: TimeInterval?
  public let playMethod: Int
  public let mediaPlayer: String?
  public let deviceInfo: DeviceInfo
  public let startedAt: Int
  public let updatedAt: Int

  public struct DeviceInfo: Codable, Sendable {
    public let deviceId: String
    public let clientVersion: String?
    public let clientName: String

    public init() {
      self.deviceId = SessionService.deviceID

      if let infoDictionary = Bundle.main.infoDictionary,
        let version = infoDictionary["CFBundleShortVersionString"] as? String,
        let build = infoDictionary["CFBundleVersion"] as? String
      {
        self.clientVersion = "\(version) (\(build))"
      } else {
        self.clientVersion = nil
      }
      self.clientName = "AudioBooth iOS"
    }
  }

  public init(
    id: String,
    libraryItemId: String,
    episodeId: String? = nil,
    mediaType: String = "book",
    duration: TimeInterval,
    startTime: TimeInterval,
    currentTime: TimeInterval,
    timeListening: TimeInterval,
    startedAt: Int,
    updatedAt: Int,
  ) {
    self.id = id
    self.libraryItemId = libraryItemId
    self.episodeId = episodeId
    self.mediaType = mediaType
    self.duration = duration
    self.startTime = startTime
    self.currentTime = currentTime
    self.timeListening = timeListening
    self.playMethod = 3
    self.mediaPlayer = "ios"
    self.deviceInfo = DeviceInfo()
    self.startedAt = startedAt
    self.updatedAt = updatedAt
  }
}
