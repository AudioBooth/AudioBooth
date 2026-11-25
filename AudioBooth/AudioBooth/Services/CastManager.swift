#if !targetEnvironment(macCatalyst)
import AVFAudio
import Combine
import Foundation
import GoogleCast
import Logging

final class CastManager: NSObject, CastClientProtocol {
  static let shared = CastManager()

  let events = PassthroughSubject<CastEvent, Never>()

  private(set) var isConnected = false

  private var isPlaying = false
  private var loadedIDs: [String] = []
  private var loadRequest: GCKRequest?
  private var seekRequest: GCKRequest?
  private var pendingAutoPlay: Bool?
  private var pendingRate: Float?
  private var pendingSeek: TimeInterval?
  private var hasHandledFinished = false
  private var positionPollTimer: Timer?

  private lazy var silentAudioPlayer: AVAudioPlayer? = {
    guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav"),
      let player = try? AVAudioPlayer(contentsOf: url)
    else { return nil }
    player.numberOfLoops = -1
    return player
  }()

  private var isAwaitingLoad: Bool { loadRequest != nil }
  private var isSeeking: Bool { seekRequest != nil }

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
      options.disableAnalyticsLogging = true
      options.stopReceiverApplicationWhenEndingSession = true
      GCKCastContext.setSharedInstanceWith(options)
    }
    sessionManager.add(self)
  }

  func load(
    streams: [(url: URL, contentType: String)],
    startIndex: Int,
    startTime: TimeInterval,
    title: String,
    author: String?,
    coverURL: URL?,
    playbackRate: Float,
    autoplay: Bool
  ) {
    guard let remoteClient else {
      AppLogger.player.error("Cast load failed: no active remote media client")
      events.send(.error)
      return
    }

    pendingAutoPlay = autoplay
    pendingRate = playbackRate
    pendingSeek = nil
    if !autoplay {
      isPlaying = false
      stopSilentAudio()
    }
    loadedIDs = streams.map(\.url.absoluteString)
    hasHandledFinished = false

    let metadata = GCKMediaMetadata(metadataType: .musicTrack)
    metadata.setString(title, forKey: kGCKMetadataKeyTitle)
    if let author {
      metadata.setString(author, forKey: kGCKMetadataKeyArtist)
    }
    if let coverURL {
      metadata.addImage(GCKImage(url: coverURL, width: 512, height: 512))
    }

    let items = streams.enumerated().map { index, stream in
      let information = GCKMediaInformationBuilder(contentURL: stream.url)
      information.contentID = stream.url.absoluteString
      information.contentType = stream.contentType
      information.streamType = .buffered
      information.metadata = metadata

      let item = GCKMediaQueueItemBuilder()
      item.mediaInformation = information.build()
      item.autoplay = index == startIndex ? autoplay : true
      item.preloadTime = 20
      if index == startIndex {
        item.startTime = startTime
      }
      return item.build()
    }

    let options = GCKMediaQueueLoadOptions()
    options.startIndex = UInt(startIndex)

    loadRequest = remoteClient.queueLoad(items, with: options)
    loadRequest?.delegate = self
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

  var hasMedia: Bool {
    isAwaitingLoad || (remoteClient?.mediaStatus.map { $0.playerState != .idle } ?? false)
  }

  func seek(to time: TimeInterval) {
    if isAwaitingLoad {
      pendingSeek = time
      return
    }

    let options = GCKMediaSeekOptions()
    options.interval = time

    seekRequest = remoteClient?.seek(with: options)
    seekRequest?.delegate = self
  }

  func setRate(_ rate: Float) {
    if isAwaitingLoad {
      pendingRate = rate
      return
    }
    remoteClient?.setPlaybackRate(rate)
  }

  private func handleSessionStarted(_ session: GCKCastSession) {
    isConnected = true
    session.remoteMediaClient?.add(self)
    events.send(.sessionStarted)
  }

  private func handleSessionEnded(error: Error?) {
    if let error {
      AppLogger.player.error("Cast session ended with error: \(error)")
    }
    isConnected = false
    isPlaying = false
    pendingAutoPlay = nil
    loadedIDs = []
    loadRequest = nil
    seekRequest = nil
    stopPositionTimer()
    stopSilentAudio()
    events.send(.sessionEnded)
  }

  private func handleRequestFinished(_ request: GCKRequest, success: Bool) {
    if request === seekRequest {
      seekRequest = nil
    }
    guard request === loadRequest else { return }
    loadRequest = nil

    let rate = pendingRate
    let seek = pendingSeek
    pendingRate = nil
    pendingSeek = nil

    guard success else {
      pendingAutoPlay = nil
      events.send(.error)
      return
    }

    if let rate {
      remoteClient?.setPlaybackRate(rate)
    }
    if let seek {
      self.seek(to: seek)
    }
    handleMediaStatusUpdate(remoteClient?.mediaStatus)
  }

  private func handleMediaStatusUpdate(_ mediaStatus: GCKMediaStatus?) {
    guard let mediaStatus else { return }

    if mediaStatus.playerState == .idle, mediaStatus.idleReason == .error {
      loadRequest = nil
      pendingAutoPlay = nil
      pendingRate = nil
      isPlaying = false
      stopSilentAudio()
      stopPositionTimer()
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
      !mediaStatus.queueHasNextItem,
      !hasHandledFinished,
      !isAwaitingLoad
    {
      hasHandledFinished = true
      isPlaying = false
      stopSilentAudio()
      stopPositionTimer()
      events.send(.finished)
      return
    }

    switch mediaStatus.playerState {
    case .playing:
      if positionPollTimer == nil {
        startPositionTimer()
      }
      setPlaying(true)
    case .paused:
      stopPositionTimer()
      setPlaying(false)
    case .idle where mediaStatus.idleReason == .cancelled && !isAwaitingLoad:
      stopPositionTimer()
      setPlaying(false)
    default:
      break
    }

    pollPosition()
  }

  private func currentIndex(in mediaStatus: GCKMediaStatus) -> Int? {
    guard let id = mediaStatus.mediaInformation?.contentID else { return nil }
    return loadedIDs.firstIndex(of: id)
  }

  private func setPlaying(_ playing: Bool) {
    guard isPlaying != playing else { return }
    isPlaying = playing
    if playing {
      startSilentAudio()
    } else {
      stopSilentAudio()
    }
    events.send(.stateChanged(isPlaying: playing))
  }

  private func startPositionTimer() {
    positionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.pollPosition() }
    }
  }

  private func stopPositionTimer() {
    positionPollTimer?.invalidate()
    positionPollTimer = nil
  }

  private func pollPosition() {
    guard !isAwaitingLoad, !isSeeking,
      let remoteClient, let mediaStatus = remoteClient.mediaStatus,
      let index = currentIndex(in: mediaStatus)
    else { return }
    let position = remoteClient.approximateStreamPosition()
    guard position > 0 else { return }
    events.send(.positionUpdated(index: index, position: position))
  }

  private func startSilentAudio() {
    AudioSession.configure()
    Task {
      await AudioSession.activate()
      guard isConnected, isPlaying else { return }
      silentAudioPlayer?.play()
    }
  }

  private func stopSilentAudio() {
    silentAudioPlayer?.stop()
  }
}

extension CastManager: GCKSessionManagerListener {
  nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
    MainActor.assumeIsolated { handleSessionStarted(session) }
  }

  nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didResumeCastSession session: GCKCastSession) {
    MainActor.assumeIsolated { handleSessionStarted(session) }
  }

  nonisolated func sessionManager(
    _ sessionManager: GCKSessionManager,
    didEnd session: GCKCastSession,
    withError error: Error?
  ) {
    MainActor.assumeIsolated { handleSessionEnded(error: error) }
  }

  nonisolated func sessionManager(
    _ sessionManager: GCKSessionManager,
    didFailToStart session: GCKCastSession,
    withError error: Error
  ) {
    MainActor.assumeIsolated { AppLogger.player.error("Cast session failed to start: \(error)") }
  }
}

extension CastManager: GCKRemoteMediaClientListener {
  nonisolated func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
    MainActor.assumeIsolated { handleMediaStatusUpdate(mediaStatus) }
  }
}

extension CastManager: GCKRequestDelegate {
  nonisolated func requestDidComplete(_ request: GCKRequest) {
    MainActor.assumeIsolated { handleRequestFinished(request, success: true) }
  }

  nonisolated func request(_ request: GCKRequest, didFailWithError error: GCKError) {
    MainActor.assumeIsolated { handleRequestFinished(request, success: false) }
  }

  nonisolated func request(_ request: GCKRequest, didAbortWith abortReason: GCKRequestAbortReason) {
    MainActor.assumeIsolated { handleRequestFinished(request, success: false) }
  }
}
#endif
