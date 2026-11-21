import Combine
import Foundation
import Logging
import Models

enum CastEvent {
  case sessionStarted
  case sessionEnded
  case positionUpdated(TimeInterval)
  case stateChanged(isPlaying: Bool)
  case trackFinished
  case error
}

protocol CastClientProtocol: AnyObject {
  var isConnected: Bool { get }
  var events: PassthroughSubject<CastEvent, Never> { get }
  func load(
    streamURL: URL,
    title: String,
    author: String?,
    coverURL: URL?,
    startTime: TimeInterval,
    playbackRate: Float,
    contentType: String,
    autoplay: Bool
  )
  func play()
  func pause()
  func seek(to time: TimeInterval, completion: ((Bool) -> Void)?)
  func setRate(_ rate: Float)
  func disconnect()
}

final class CastPlaybackController {
  enum Event {
    case timeUpdate(TimeInterval)
    case stateChanged(AudioPlayer.PlaybackState)
    case seek(TimeInterval)
    case rateChanged(Float)
    case finished
    case error(Error?)
    case sessionStarted
    case sessionEnded
    case sessionUpdated(PlaybackSession)
    case trackChanged(Int)
  }

  var onRequireRemoteSession: (() async -> PlaybackSession?)?
  var onCastSessionEnded: (() -> Void)?

  private(set) var currentTrackIndex: Int = 0
  private(set) var isPlaying: Bool = false
  private(set) var isBuffering: Bool = false

  var isPlaybackActive: Bool {
    isPlaying || isBuffering
  }

  static var isDefaultSessionActive: Bool {
    #if canImport(GoogleCast) && !targetEnvironment(macCatalyst) && !os(watchOS)
    CastManager.isSessionActive
    #else
    false
    #endif
  }

  private static func defaultClient() -> CastClientProtocol? {
    #if canImport(GoogleCast) && !targetEnvironment(macCatalyst) && !os(watchOS)
    CastManager.shared
    #else
    nil
    #endif
  }

  var isConnected: Bool {
    injectedClient?.isConnected ?? Self.isDefaultSessionActive
  }

  let events = PassthroughSubject<Event, Never>()

  private let injectedClient: CastClientProtocol?
  private var activeClient: CastClientProtocol? {
    injectedClient ?? Self.defaultClient()
  }

  private var pendingSeekTarget: TimeInterval?
  private var tracks: [Track] = []
  private var session: PlaybackSession?
  private var coverURL: URL?
  private var playbackRate: Float = 1.0
  private var wantsPlayback: Bool = false
  private var reportedTime: TimeInterval?
  private var loadGeneration: UInt64 = 0
  private var loadTask: Task<Void, Never>?
  private var cancellables = Set<AnyCancellable>()

  init(client: CastClientProtocol? = nil) {
    self.injectedClient = client
    activeClient?.events
      .sink { [weak self] event in
        self?.handleCastEvent(event)
      }
      .store(in: &cancellables)
  }

  func updateContext(
    session: PlaybackSession,
    tracks: [Track],
    currentTrackIndex: Int,
    coverURL: URL?,
    rate: Float,
    wantsPlayback: Bool
  ) {
    self.session = session
    self.tracks = tracks
    self.currentTrackIndex = currentTrackIndex
    self.coverURL = coverURL
    self.playbackRate = rate
    self.wantsPlayback = wantsPlayback
  }

  func load(
    session: PlaybackSession,
    tracks: [Track],
    trackIndex: Int,
    offset: TimeInterval,
    coverURL: URL?,
    rate: Float,
    autoPlay: Bool
  ) {
    loadGeneration &+= 1
    let generation = loadGeneration
    loadTask?.cancel()
    loadTask = nil

    self.session = session
    self.tracks = tracks
    self.currentTrackIndex = trackIndex
    self.coverURL = coverURL
    self.playbackRate = rate
    self.wantsPlayback = autoPlay
    self.pendingSeekTarget = nil

    guard tracks.indices.contains(trackIndex) else {
      isBuffering = false
      events.send(.error(nil))
      return
    }

    let track = tracks[trackIndex]
    self.reportedTime = track.startOffset + offset

    if let url = session.remoteURL(for: track) {
      castLoad(track: track, url: url, offset: offset, autoPlay: autoPlay)
      return
    }

    if autoPlay {
      isBuffering = true
    }

    loadTask = Task { [weak self] in
      defer {
        if self?.loadGeneration == generation {
          self?.loadTask = nil
        }
      }
      guard let self, !Task.isCancelled, self.loadGeneration == generation else { return }

      let remoteSession = await self.onRequireRemoteSession?()
      guard !Task.isCancelled, self.loadGeneration == generation else { return }

      guard let remoteSession else {
        self.isBuffering = false
        self.events.send(.error(nil))
        return
      }

      self.session = remoteSession
      self.events.send(.sessionUpdated(remoteSession))

      let resolvedTracks = remoteSession.tracks.isEmpty ? self.tracks : remoteSession.tracks
      self.tracks = resolvedTracks

      guard resolvedTracks.indices.contains(trackIndex),
            let url = remoteSession.remoteURL(for: resolvedTracks[trackIndex]) else {
        self.isBuffering = false
        self.events.send(.error(nil))
        return
      }

      self.castLoad(
        track: resolvedTracks[trackIndex],
        url: url,
        offset: offset,
        autoPlay: self.wantsPlayback
      )
    }
  }

  func play() {
    wantsPlayback = true
    if loadTask != nil {
      isBuffering = true
      events.send(.stateChanged(.buffering))
      return
    }
    isBuffering = !isPlaying
    activeClient?.play()
  }

  func pause() {
    let hadPendingLoad = loadTask != nil || isBuffering
    wantsPlayback = false
    loadGeneration &+= 1
    loadTask?.cancel()
    loadTask = nil
    isBuffering = false
    activeClient?.pause()
    if hadPendingLoad && !isPlaying {
      events.send(.stateChanged(.paused))
    }
  }

  func stop() {
    wantsPlayback = false
    isPlaying = false
    isBuffering = false
    pendingSeekTarget = nil
    reportedTime = nil
    loadGeneration &+= 1
    loadTask?.cancel()
    loadTask = nil
    activeClient?.pause()
  }

  func seek(to time: TimeInterval) {
    let (targetIndex, offset) = tracks.trackAndOffset(for: time)
    let clampedTime = tracks.indices.contains(targetIndex)
      ? tracks[targetIndex].startOffset + offset
      : max(0, time)
    reportedTime = clampedTime
    events.send(.seek(clampedTime))

    if (targetIndex != currentTrackIndex || loadTask != nil), let session {
      if targetIndex != currentTrackIndex {
        currentTrackIndex = targetIndex
        events.send(.trackChanged(targetIndex))
      }
      load(
        session: session,
        tracks: tracks,
        trackIndex: targetIndex,
        offset: offset,
        coverURL: coverURL,
        rate: playbackRate,
        autoPlay: wantsPlayback
      )
      return
    }

    pendingSeekTarget = clampedTime
    activeClient?.seek(to: offset) { [weak self] _ in
      guard let self, self.pendingSeekTarget == clampedTime else { return }
      self.pendingSeekTarget = nil
    }
  }

  func setRate(_ rate: Float) {
    playbackRate = rate
    activeClient?.setRate(rate)
    events.send(.rateChanged(rate))
  }

  func currentTime(fallback: TimeInterval) -> TimeInterval {
    if let pendingSeekTarget {
      return pendingSeekTarget
    }
    return reportedTime ?? fallback
  }

  func isPositioned(at target: TimeInterval, fallback: TimeInterval) -> Bool {
    if let pendingSeekTarget {
      return abs(pendingSeekTarget - target) <= 1
    }
    return abs(currentTime(fallback: fallback) - target) <= 1
  }
}

private extension CastPlaybackController {
  func castLoad(track: Track, url: URL, offset: TimeInterval, autoPlay: Bool) {
    activeClient?.load(
      streamURL: url,
      title: session?.displayTitle ?? "Audiobook",
      author: session?.displayAuthor,
      coverURL: coverURL,
      startTime: offset,
      playbackRate: playbackRate,
      contentType: track.mimeType ?? "audio/mpeg",
      autoplay: autoPlay
    )
  }

  func handleCastEvent(_ event: CastEvent) {
    switch event {
    case .sessionStarted:
      AppLogger.player.info("Cast session started")
      events.send(.sessionStarted)

    case .sessionEnded:
      AppLogger.player.info("Cast session ended")
      loadGeneration &+= 1
      loadTask?.cancel()
      loadTask = nil
      isPlaying = false
      isBuffering = false
      pendingSeekTarget = nil
      onCastSessionEnded?()
      events.send(.sessionEnded)

    case .positionUpdated(let position):
      handlePositionUpdated(position)

    case .stateChanged(let isNowPlaying):
      isPlaying = isNowPlaying
      isBuffering = false
      events.send(.stateChanged(isNowPlaying ? .playing : .paused))

    case .trackFinished:
      handleTrackFinished()

    case .error:
      isPlaying = false
      isBuffering = false
      events.send(.error(nil))
    }
  }

  func handlePositionUpdated(_ trackPosition: TimeInterval) {
    let globalTime: TimeInterval
    if tracks.indices.contains(currentTrackIndex) {
      let track = tracks[currentTrackIndex]
      globalTime = track.startOffset + min(max(0, trackPosition), track.duration)
    } else {
      globalTime = max(0, trackPosition)
    }

    if let target = pendingSeekTarget {
      guard abs(globalTime - target) <= 2 else { return }
      pendingSeekTarget = nil
    }

    reportedTime = globalTime
    events.send(.timeUpdate(globalTime))
  }

  func handleTrackFinished() {
    let nextIndex = currentTrackIndex + 1
    guard tracks.indices.contains(nextIndex), let session else {
      wantsPlayback = false
      isPlaying = false
      isBuffering = false
      events.send(.stateChanged(.paused))
      events.send(.finished)
      return
    }

    currentTrackIndex = nextIndex
    events.send(.trackChanged(nextIndex))
    load(
      session: session,
      tracks: tracks,
      trackIndex: nextIndex,
      offset: 0,
      coverURL: coverURL,
      rate: playbackRate,
      autoPlay: true
    )
  }
}
