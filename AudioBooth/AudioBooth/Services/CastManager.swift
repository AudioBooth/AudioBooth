#if canImport(GoogleCast) && !os(watchOS)
import AVFAudio
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
  @Published private(set) var currentStreamURL: URL?

  private var remoteClient: GCKRemoteMediaClient?
  private var hasHandledTrackFinished = false
  private var hasReceivedInitialVolume = false
  private var lastReportedVolume: Float?
  private var lastReportedMuted: Bool?

  private var silentAudioPlayer: AVAudioPlayer?
  private var positionPollTimer: Timer?

  var onPositionUpdate: ((TimeInterval) -> Void)?
  var onStateChange: ((Bool) -> Void)?
  var onSessionEnded: (() -> Void)?
  var onSessionStarted: (() -> Void)?
  var onTrackFinished: (() -> Void)?
  var onError: (() -> Void)?

  override private init() {
    super.init()
    let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
    let options = GCKCastOptions(discoveryCriteria: criteria)
    options.suspendSessionsWhenBackgrounded = false
    options.physicalVolumeButtonsWillControlDeviceVolume = true
    GCKCastContext.setSharedInstanceWith(options)
    GCKCastContext.sharedInstance().sessionManager.add(self)
    setupSilentAudioPlayer()
  }

  private func setupSilentAudioPlayer() {
    let header: [UInt8] = [
      0x52, 0x49, 0x46, 0x46, 0xA4, 0x3E, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45, 0x66, 0x6D, 0x74, 0x20,
      0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x40, 0x1F, 0x00, 0x00, 0x80, 0x3E, 0x00, 0x00,
      0x02, 0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61, 0x80, 0x3E, 0x00, 0x00
    ]
    var data = Data(header)
    data.append(Data(count: 16000))

    silentAudioPlayer = try? AVAudioPlayer(data: data)
    silentAudioPlayer?.numberOfLoops = -1
    silentAudioPlayer?.volume = 0.0
    silentAudioPlayer?.prepareToPlay()
  }

  private func startSilentAudio() {
    AudioSession.configure()
    Task { @MainActor [weak self] in
      await AudioSession.activate()
      guard let self, self.isPlaying else { return }
      self.silentAudioPlayer?.play()
    }
    startPositionPolling()
  }

  private func stopSilentAudio() {
    silentAudioPlayer?.pause()
    stopPositionPolling()
  }

  private func startPositionPolling() {
    positionPollTimer?.invalidate()
    positionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, let client = self.remoteClient, self.isPlaying else { return }
        let pos = client.approximateStreamPosition()
        if pos > 0 {
          self.currentPosition = pos
          self.onPositionUpdate?(pos)
        }
      }
    }
  }

  private func stopPositionPolling() {
    positionPollTimer?.invalidate()
    positionPollTimer = nil
  }

  func load(
    streamURL: URL,
    title: String,
    author: String?,
    coverURL: URL?,
    startTime: TimeInterval,
    playbackRate: Float = 1.0,
    contentType: String = "audio/mpeg",
    autoplay: Bool = true
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
    loadOptions.autoplay = autoplay
    loadOptions.playbackRate = playbackRate

    currentPosition = startTime
    currentStreamURL = streamURL

    let wasPlaying = isPlaying
    isPlaying = autoplay
    if autoplay {
      startSilentAudio()
      if !wasPlaying {
        onStateChange?(true)
      }
    } else {
      stopSilentAudio()
      if wasPlaying {
        onStateChange?(false)
      }
    }
    client.loadMedia(builder.build(), with: loadOptions)
  }

  func play() {
    isPlaying = true
    startSilentAudio()
    onStateChange?(true)
    remoteClient?.play()
  }

  func pause() {
    isPlaying = false
    stopSilentAudio()
    onStateChange?(false)
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
    stopSilentAudio()
    GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
  }

  private func handleDeviceVolumeChange(_ volume: Float, muted: Bool) {
    guard hasReceivedInitialVolume else {
      hasReceivedInitialVolume = true
      lastReportedVolume = volume
      lastReportedMuted = muted
      return
    }

    let volumeChanged = lastReportedVolume.map { abs($0 - volume) >= 0.005 } ?? true
    let muteChanged = lastReportedMuted != muted
    guard volumeChanged || muteChanged else { return }

    lastReportedVolume = volume
    lastReportedMuted = muted

    let name = deviceName ?? "Speaker"
    let percent = Int(round(volume * 100))
    let message = muted ? "\(name) • Muted" : "\(name) • \(percent)%"
    Toast(volume: message).show()
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
      self.hasReceivedInitialVolume = false
      self.lastReportedVolume = nil
      self.lastReportedMuted = nil
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
      self.hasReceivedInitialVolume = false
      self.lastReportedVolume = nil
      self.lastReportedMuted = nil
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
      self.stopSilentAudio()
      self.isConnected = false
      self.isPlaying = false
      self.deviceName = nil
      self.remoteClient?.remove(self)
      self.remoteClient = nil
      self.currentPosition = 0
      self.currentStreamURL = nil
      self.hasReceivedInitialVolume = false
      self.lastReportedVolume = nil
      self.lastReportedMuted = nil
      self.onSessionEnded?()
    }
  }

  nonisolated func sessionManager(
    _ sessionManager: GCKSessionManager,
    didFailToStart session: GCKSession,
    withError error: any Error
  ) {
    Task { @MainActor in
      self.stopSilentAudio()
      self.isConnected = false
      self.isPlaying = false
      self.deviceName = nil
      self.remoteClient?.remove(self)
      self.remoteClient = nil
      self.currentPosition = 0
      self.currentStreamURL = nil
      self.hasReceivedInitialVolume = false
      self.lastReportedVolume = nil
      self.lastReportedMuted = nil
      self.onError?()
      self.onSessionEnded?()
    }
  }

  nonisolated func sessionManager(
    _ sessionManager: GCKSessionManager,
    session: GCKSession,
    didReceiveDeviceVolume volume: Float,
    muted: Bool
  ) {
    Task { @MainActor in
      self.handleDeviceVolumeChange(volume, muted: muted)
    }
  }

  nonisolated func sessionManager(
    _ sessionManager: GCKSessionManager,
    castSession: GCKCastSession,
    didReceiveDeviceVolume volume: Float,
    muted: Bool
  ) {
    Task { @MainActor in
      self.handleDeviceVolumeChange(volume, muted: muted)
    }
  }
}

extension CastManager: GCKRemoteMediaClientListener {
  nonisolated func remoteMediaClient(
    _ client: GCKRemoteMediaClient,
    didUpdate mediaStatus: GCKMediaStatus?
  ) {
    Task { @MainActor in
      guard let mediaStatus else { return }

      let isActuallyPaused = mediaStatus.playerState == .paused || (mediaStatus.playerState == .idle && mediaStatus.idleReason == .cancelled)

      if isActuallyPaused && self.isPlaying {
        self.isPlaying = false
        self.stopSilentAudio()
        self.onStateChange?(false)
      } else if mediaStatus.playerState == .playing && !self.isPlaying {
        self.isPlaying = true
        self.startSilentAudio()
        self.onStateChange?(true)
      }

      if mediaStatus.idleReason == .finished {
        if !self.hasHandledTrackFinished {
          self.hasHandledTrackFinished = true
          self.onTrackFinished?()
        }
      } else if mediaStatus.idleReason == .error {
        self.onError?()
      } else if mediaStatus.playerState == .playing || mediaStatus.playerState == .buffering {
        self.hasHandledTrackFinished = false
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
