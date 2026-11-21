#if canImport(GoogleCast) && !targetEnvironment(macCatalyst) && !os(watchOS)
import AVFAudio
import Combine
import Foundation
import GoogleCast
import Logging

final class CastManager: NSObject, CastClientProtocol {
  private static var _shared: CastManager?

  static var isSessionActive: Bool { _shared?.isConnected ?? false }

  static var shared: CastManager {
    if let instance = _shared { return instance }
    let instance = CastManager()
    _shared = instance
    return instance
  }

  let events = PassthroughSubject<CastEvent, Never>()

  private(set) var isConnected = false
  private(set) var isPlaying = false
  private(set) var currentPosition: TimeInterval = 0
  private(set) var currentStreamURL: URL?

  private var isAwaitingLoad = false
  private var isSeeking = false
  private var pendingAutoPlay: Bool?
  private var pendingRate: Float?
  private var hasHandledTrackFinished = false
  private var positionPollTimer: Timer?
  private var silentAudioPlayer: AVAudioPlayer?
  private var activeLoadRequest: (id: ObjectIdentifier, delegate: CastRequestDelegate)?
  private var activeSeekDelegates: [ObjectIdentifier: CastRequestDelegate] = [:]

  private var sessionManager: GCKSessionManager {
    GCKCastContext.sharedInstance().sessionManager
  }

  private var remoteClient: GCKRemoteMediaClient? {
    sessionManager.currentCastSession?.remoteMediaClient
  }

  private override init() {
    super.init()
    if !GCKCastContext.isSharedInstanceInitialized() {
      let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
      let options = GCKCastOptions(discoveryCriteria: criteria)
      options.suspendSessionsWhenBackgrounded = false
      options.physicalVolumeButtonsWillControlDeviceVolume = true
      GCKCastContext.setSharedInstanceWith(options)
    }
    sessionManager.add(self)
  }

  func load(
    streamURL: URL,
    title: String,
    author: String?,
    coverURL: URL?,
    startTime: TimeInterval = 0,
    playbackRate: Float = 1.0,
    contentType: String = "audio/mpeg",
    autoplay: Bool = true
  ) {
    guard let remoteClient else {
      AppLogger.player.error("Cast load failed: no active remote media client")
      events.send(.error)
      return
    }

    isAwaitingLoad = true
    pendingAutoPlay = autoplay
    pendingRate = nil
    isSeeking = false
    isPlaying = false
    stopSilentAudio()
    currentPosition = startTime
    currentStreamURL = streamURL
    hasHandledTrackFinished = false

    let metadata = GCKMediaMetadata(metadataType: .musicTrack)
    metadata.setString(title, forKey: kGCKMetadataKeyTitle)
    if let author {
      metadata.setString(author, forKey: kGCKMetadataKeyArtist)
    }
    if let coverURL {
      metadata.addImage(GCKImage(url: coverURL, width: 512, height: 512))
    }

    let builder = GCKMediaInformationBuilder(contentURL: streamURL)
    builder.contentType = contentType
    builder.streamType = .buffered
    builder.metadata = metadata

    let options = GCKMediaLoadOptions()
    options.autoplay = autoplay
    options.playPosition = startTime
    options.playbackRate = playbackRate

    let request = remoteClient.loadMedia(builder.build(), with: options)
    let id = ObjectIdentifier(request)
    let delegate = CastRequestDelegate { [weak self] success in
      guard let self, self.activeLoadRequest?.id == id else { return }
      self.activeLoadRequest = nil
      if !success {
        self.isAwaitingLoad = false
        self.pendingAutoPlay = nil
        self.pendingRate = nil
        self.events.send(.error)
      }
    }
    activeLoadRequest = (id, delegate)
    request.delegate = delegate
  }

  func play() {
    if isAwaitingLoad {
      pendingAutoPlay = true
      return
    }
    remoteClient?.play()
  }

  func pause() {
    if isAwaitingLoad {
      pendingAutoPlay = false
      return
    }
    stopSilentAudio()
    remoteClient?.pause()
  }

  func seek(to time: TimeInterval, completion: ((Bool) -> Void)? = nil) {
    isSeeking = true
    currentPosition = time

    let options = GCKMediaSeekOptions()
    options.interval = time

    guard let request = remoteClient?.seek(with: options) else {
      isSeeking = !activeSeekDelegates.isEmpty
      completion?(false)
      return
    }

    let key = ObjectIdentifier(request)
    let delegate = CastRequestDelegate { [weak self] success in
      guard let self else {
        completion?(success)
        return
      }
      self.activeSeekDelegates.removeValue(forKey: key)
      self.isSeeking = !self.activeSeekDelegates.isEmpty
      completion?(success)
    }
    activeSeekDelegates[key] = delegate
    request.delegate = delegate
  }

  func setRate(_ rate: Float) {
    if isAwaitingLoad {
      pendingRate = rate
      return
    }
    remoteClient?.setPlaybackRate(rate)
  }

  func disconnect() {
    sessionManager.endSessionAndStopCasting(true)
  }

  private func handleSessionStarted(_ session: GCKCastSession) {
    isConnected = true
    session.remoteMediaClient?.add(self)
    startPositionTimer()
    events.send(.sessionStarted)
  }

  private func handleSessionEnded(error: Error?) {
    if let error {
      AppLogger.player.error("Cast session ended with error: \(error)")
    }
    isConnected = false
    isPlaying = false
    isAwaitingLoad = false
    isSeeking = false
    pendingAutoPlay = nil
    pendingRate = nil
    currentStreamURL = nil
    activeLoadRequest = nil
    activeSeekDelegates.removeAll()
    stopPositionTimer()
    stopSilentAudio()
    events.send(.sessionEnded)
  }

  private func handleSessionFailed(error: Error) {
    AppLogger.player.error("Cast session failed to start: \(error)")
    isConnected = false
    isPlaying = false
    isAwaitingLoad = false
    pendingAutoPlay = nil
    pendingRate = nil
    activeLoadRequest = nil
  }

  private func handleMediaStatusUpdate(_ mediaStatus: GCKMediaStatus?) {
    guard let mediaStatus else { return }

    if isAwaitingLoad {
      let urlMatches = mediaStatus.mediaInformation?.contentURL == currentStreamURL
      let isActiveState =
        mediaStatus.playerState == .playing
        || mediaStatus.playerState == .buffering
        || mediaStatus.playerState == .paused
      if urlMatches || (mediaStatus.mediaInformation?.contentURL == nil && isActiveState) {
        isAwaitingLoad = false
        if let rate = pendingRate {
          pendingRate = nil
          remoteClient?.setPlaybackRate(rate)
        }
      }
    }

    if mediaStatus.playerState == .idle, mediaStatus.idleReason == .error {
      isAwaitingLoad = false
      pendingAutoPlay = nil
      pendingRate = nil
      isPlaying = false
      stopSilentAudio()
      events.send(.error)
      return
    }

    if !isAwaitingLoad,
       let desiredPlay = pendingAutoPlay,
       mediaStatus.playerState == .playing || mediaStatus.playerState == .paused
    {
      pendingAutoPlay = nil
      if desiredPlay, mediaStatus.playerState == .paused {
        remoteClient?.play()
      } else if !desiredPlay, mediaStatus.playerState == .playing {
        remoteClient?.pause()
      }
    }

    if mediaStatus.playerState == .idle,
       mediaStatus.idleReason == .finished,
       !hasHandledTrackFinished,
       !isAwaitingLoad
    {
      hasHandledTrackFinished = true
      isPlaying = false
      stopSilentAudio()
      stopPositionTimer()
      events.send(.trackFinished)
      return
    }

    switch mediaStatus.playerState {
    case .playing:
      if positionPollTimer == nil {
        startPositionTimer()
      }
      if !isPlaying {
        isPlaying = true
        startSilentAudio()
        events.send(.stateChanged(isPlaying: true))
      }
    case .paused:
      if isPlaying {
        isPlaying = false
        stopSilentAudio()
        events.send(.stateChanged(isPlaying: false))
      }
    case .idle where mediaStatus.idleReason == .cancelled && !isAwaitingLoad:
      if isPlaying {
        isPlaying = false
        stopSilentAudio()
        events.send(.stateChanged(isPlaying: false))
      }
    default:
      break
    }

    let pos = mediaStatus.streamPosition
    if !isAwaitingLoad, !isSeeking, pos > 0 {
      currentPosition = pos
      events.send(.positionUpdated(pos))
    }
  }

  private func startPositionTimer() {
    stopPositionTimer()
    positionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { self?.pollPosition() }
    }
  }

  private func stopPositionTimer() {
    positionPollTimer?.invalidate()
    positionPollTimer = nil
  }

  private func pollPosition() {
    guard !isAwaitingLoad, !isSeeking else { return }
    guard let pos = remoteClient?.approximateStreamPosition(), pos > 0 else { return }
    currentPosition = pos
    events.send(.positionUpdated(pos))
  }

  private func startSilentAudio() {
    AudioSession.configure()
    Task {
      await AudioSession.activate()
      guard isConnected, isPlaying else { return }
      if silentAudioPlayer == nil {
        silentAudioPlayer = makeSilentAudioPlayer()
      }
      silentAudioPlayer?.play()
    }
  }

  private func stopSilentAudio() {
    silentAudioPlayer?.stop()
    silentAudioPlayer = nil
  }

  private func makeSilentAudioPlayer() -> AVAudioPlayer? {
    let sampleRate: UInt32 = 8000
    let dataSize: UInt32 = 1600
    let chunkSize = 36 + dataSize

    var data = Data(capacity: 44 + Int(dataSize))
    data.append(contentsOf: "RIFF".utf8)
    data.appendLittleEndian(chunkSize)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    data.appendLittleEndian(UInt32(16))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(sampleRate)
    data.appendLittleEndian(sampleRate * 2)
    data.appendLittleEndian(UInt16(2))
    data.appendLittleEndian(UInt16(16))
    data.append(contentsOf: "data".utf8)
    data.appendLittleEndian(dataSize)
    data.append(Data(count: Int(dataSize)))

    do {
      let player = try AVAudioPlayer(data: data)
      player.numberOfLoops = -1
      player.volume = 0
      player.prepareToPlay()
      return player
    } catch {
      AppLogger.player.error("Failed to create silent audio player: \(error)")
      return nil
    }
  }
}

extension CastManager: GCKSessionManagerListener {
  nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
    Task { await self.handleSessionStarted(session) }
  }

  nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didResumeCastSession session: GCKCastSession) {
    Task { await self.handleSessionStarted(session) }
  }

  nonisolated func sessionManager(
    _ sessionManager: GCKSessionManager,
    didEnd session: GCKCastSession,
    withError error: Error?
  ) {
    Task { await self.handleSessionEnded(error: error) }
  }

  nonisolated func sessionManager(
    _ sessionManager: GCKSessionManager,
    didFailToStart session: GCKCastSession,
    withError error: Error
  ) {
    Task { await self.handleSessionFailed(error: error) }
  }
}

extension CastManager: GCKRemoteMediaClientListener {
  nonisolated func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
    Task { await self.handleMediaStatusUpdate(mediaStatus) }
  }
}

private final class CastRequestDelegate: NSObject, GCKRequestDelegate {
  private let onComplete: (Bool) -> Void

  init(onComplete: @escaping (Bool) -> Void) {
    self.onComplete = onComplete
  }

  private func finish(_ success: Bool) {
    onComplete(success)
  }

  nonisolated func requestDidComplete(_ request: GCKRequest) {
    Task { await self.finish(true) }
  }

  nonisolated func request(_ request: GCKRequest, didFailWithError error: GCKError) {
    Task { await self.finish(false) }
  }

  nonisolated func request(_ request: GCKRequest, didAbortWith abortReason: GCKRequestAbortReason) {
    Task { await self.finish(false) }
  }
}

private extension Data {
  mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    var little = value.littleEndian
    Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
  }
}
#endif
