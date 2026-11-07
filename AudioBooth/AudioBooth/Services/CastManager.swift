#if canImport(GoogleCast) && !os(watchOS)
import Combine
import Foundation
import GoogleCast

@MainActor
final class CastManager: NSObject, ObservableObject {
  static let shared = CastManager()

  @Published private(set) var isConnected = false
  @Published private(set) var isPlaying = false
  @Published private(set) var currentPosition: TimeInterval = 0
  @Published private(set) var deviceName: String?

  private var remoteClient: GCKRemoteMediaClient?
  var onPositionUpdate: ((TimeInterval) -> Void)?
  var onStateChange: ((Bool) -> Void)?
  var onSessionEnded: (() -> Void)?
  var onSessionStarted: (() -> Void)?

  override private init() {
    super.init()
    let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
    let options = GCKCastOptions(discoveryCriteria: criteria)
    options.suspendSessionsWhenBackgrounded = false
    options.physicalVolumeButtonsWillControlDeviceVolume = true
    GCKCastContext.setSharedInstanceWith(options)
    GCKCastContext.sharedInstance().sessionManager.add(self)
  }

  func load(
    streamURL: URL,
    title: String,
    author: String?,
    coverURL: URL?,
    startTime: TimeInterval,
    contentType: String = "audio/mpeg"
  ) {
    guard let client = remoteClient else { return }

    let metadata = GCKMediaMetadata(metadataType: .musicTrack)
    metadata.setString(title, forKey: kGCKMetadataKeyTitle)
    if let author {
      metadata.setString(author, forKey: kGCKMetadataKeyArtist)
    }
    if let coverURL {
      metadata.addImage(GCKImage(url: coverURL, width: 480, height: 480))
    }

    let builder = GCKMediaInformationBuilder(contentURL: streamURL)
    builder.streamType = .buffered
    builder.contentType = contentType
    builder.metadata = metadata

    let loadOptions = GCKMediaLoadOptions()
    loadOptions.playPosition = startTime
    loadOptions.autoplay = true

    client.loadMedia(builder.build(), with: loadOptions)
  }

  func play() {
    remoteClient?.play()
  }

  func pause() {
    remoteClient?.pause()
  }

  func seek(to time: TimeInterval) {
    let options = GCKMediaSeekOptions()
    options.interval = time
    options.resumeState = isPlaying ? .play : .pause
    remoteClient?.seek(with: options)
  }

  func setRate(_ rate: Float) {
    remoteClient?.setPlaybackRate(rate)
  }

  func setVolume(_ volume: Float) {
    remoteClient?.setStreamVolume(volume)
  }

  func disconnect() {
    GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
  }
}

extension CastManager: GCKSessionManagerListener {
  nonisolated func sessionManager(
    _ sessionManager: GCKSessionManager,
    didStart session: GCKSession
  ) {
    Task { @MainActor in
      guard let castSession = session as? GCKCastSession else { return }
      self.isConnected = true
      self.deviceName = castSession.device.friendlyName
      self.remoteClient = castSession.remoteMediaClient
      castSession.remoteMediaClient?.add(self)
      self.onSessionStarted?()
    }
  }

  nonisolated func sessionManager(
    _ sessionManager: GCKSessionManager,
    didResume session: GCKSession
  ) {
    Task { @MainActor in
      guard let castSession = session as? GCKCastSession else { return }
      self.isConnected = true
      self.deviceName = castSession.device.friendlyName
      self.remoteClient = castSession.remoteMediaClient
      castSession.remoteMediaClient?.add(self)
      self.onSessionStarted?()
    }
  }

  nonisolated func sessionManager(
    _ sessionManager: GCKSessionManager,
    didEnd session: GCKSession,
    withError error: (any Error)?
  ) {
    Task { @MainActor in
      self.isConnected = false
      self.isPlaying = false
      self.deviceName = nil
      self.remoteClient = nil
      self.onSessionEnded?()
    }
  }
}

extension CastManager: GCKRemoteMediaClientListener {
  nonisolated func remoteMediaClient(
    _ client: GCKRemoteMediaClient,
    didUpdate mediaStatus: GCKMediaStatus?
  ) {
    Task { @MainActor in
      let nowPlaying = mediaStatus?.playerState == .playing
      if self.isPlaying != nowPlaying {
        self.isPlaying = nowPlaying
        self.onStateChange?(nowPlaying)
      }
      let position = client.approximateStreamPosition()
      if position > 0 {
        self.currentPosition = position
        self.onPositionUpdate?(position)
      }
    }
  }
}
#endif
