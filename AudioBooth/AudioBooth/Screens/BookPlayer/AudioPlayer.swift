import AVFoundation
import Combine
import Logging
import Models

final class AudioPlayer {
  enum PlaybackState {
    case playing
    case paused
    case stopped
    case buffering
    case ready
    case error
  }

  enum Event {
    case timeUpdate(TimeInterval)
    case stateChanged(PlaybackState)
    case seek(TimeInterval)
    case rateChanged(Float)
    case finished
    case stalled
    case error(Error?)
  }

  private let player = AVPlayer()
  private let eqContext = EQContext()
  private let mediaProgress: MediaProgress
  private var tracks: [Track] = []
  private var trackURLs: [URL] = []
  private(set) var currentTrackIndex: Int = 0
  private var isPrepared: Bool = false
  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  private var itemObservers = Set<AnyCancellable>()

  let events = PassthroughSubject<Event, Never>()

  var time: TimeInterval {
    if isPrepared { return mediaProgress.currentTime }
    guard !tracks.isEmpty else { return player.currentSeconds }
    return tracks[currentTrackIndex].startOffset + player.currentSeconds
  }

  var duration: TimeInterval {
    let d = player.currentItem?.duration.seconds ?? 0
    return d.isNaN ? 0 : d
  }

  var isPlaying: Bool {
    player.timeControlStatus == .playing
  }

  var isBuffering: Bool {
    player.timeControlStatus == .waitingToPlayAtSpecifiedRate
  }

  var hasContent: Bool {
    !trackURLs.isEmpty
  }

  var volume: Float {
    get { player.volume }
    set { player.volume = newValue }
  }

  var rate: Float {
    get { player.defaultRate }
    set {
      player.defaultRate = newValue
      if player.timeControlStatus == .playing {
        player.rate = newValue
      }
      events.send(.rateChanged(newValue))
    }
  }

  init(mediaProgress: MediaProgress) {
    self.mediaProgress = mediaProgress
    player.allowsExternalPlayback = false
    setupObservers()
  }

  deinit {
    removeTimeObserver()
  }

  func prepare(
    tracks: [Track],
    urlResolver: (Track) -> URL?
  ) {
    var resolvedTracks: [Track] = []
    var urls: [URL] = []
    for track in tracks {
      guard let url = urlResolver(track) else { continue }
      resolvedTracks.append(track)
      urls.append(url)
    }
    self.tracks = resolvedTracks
    self.trackURLs = urls
    self.isPrepared = !urls.isEmpty

    addTimeObserver()
  }

  func pause() {
    player.pause()
  }

  func resume() {
    if isPrepared {
      isPrepared = false
      guard !trackURLs.isEmpty else {
        events.send(.error(nil))
        return
      }

      let (trackIndex, offset) = trackAndOffset(for: mediaProgress.currentTime)
      currentTrackIndex = trackIndex
      loadTrack(at: trackIndex, seekTo: offset, autoPlay: true)
    } else if player.currentItem != nil, player.currentItem?.status != .failed {
      player.play()
    } else {
      let (trackIndex, offset) = trackAndOffset(for: mediaProgress.currentTime)
      currentTrackIndex = trackIndex
      loadTrack(at: trackIndex, seekTo: offset, autoPlay: true)
    }
  }

  func stop() {
    removeTimeObserver()
    player.pause()
    player.replaceCurrentItem(with: nil)
    events.send(.stateChanged(.stopped))
  }

  func seek(to time: TimeInterval) {
    if isPrepared {
      events.send(.timeUpdate(time))
      events.send(.seek(time))
      return
    }

    guard !tracks.isEmpty else {
      player.seek(to: CMTime(seconds: time, preferredTimescale: 1000)) { [weak self] _ in
        self?.events.send(.seek(time))
      }
      return
    }

    let (targetIndex, offset) = trackAndOffset(for: time)

    if targetIndex == currentTrackIndex {
      player.seek(to: CMTime(seconds: offset, preferredTimescale: 1000)) { [weak self] _ in
        self?.events.send(.seek(time))
      }
      return
    }

    currentTrackIndex = targetIndex
    guard targetIndex < trackURLs.count else { return }
    loadTrack(at: targetIndex, seekTo: offset, autoPlay: isPlaying)
    events.send(.seek(time))
  }

  func rebuildQueue(urlResolver: (Track) -> URL?) {
    let currentGlobal = time
    let wasPlaying = isPlaying

    var resolvedTracks: [Track] = []
    var urls: [URL] = []
    for track in tracks {
      guard let url = urlResolver(track) else { continue }
      resolvedTracks.append(track)
      urls.append(url)
    }
    self.tracks = resolvedTracks
    self.trackURLs = urls

    guard !urls.isEmpty else { return }

    let (trackIndex, offset) = trackAndOffset(for: currentGlobal)
    currentTrackIndex = trackIndex
    loadTrack(at: trackIndex, seekTo: offset, autoPlay: wasPlaying)
  }
}

private extension AudioPlayer {
  func loadTrack(at index: Int, seekTo offset: TimeInterval, autoPlay: Bool) {
    guard index < trackURLs.count else { return }

    let item = AVPlayerItem(url: trackURLs[index])
    observeItem(item)
    player.replaceCurrentItem(with: item)

    if offset > 0 {
      player.seek(to: CMTime(seconds: offset, preferredTimescale: 1000)) { [weak self] _ in
        guard let self, autoPlay else { return }
        self.player.play()
        self.player.rate = self.player.defaultRate
      }
    } else if autoPlay {
      player.play()
      player.rate = player.defaultRate
    }
  }

  func advanceToNextTrack() {
    guard currentTrackIndex < tracks.count - 1 else {
      events.send(.finished)
      return
    }

    currentTrackIndex += 1
    AppLogger.player.debug("Advanced to track \(self.currentTrackIndex)/\(self.tracks.count)")
    loadTrack(at: currentTrackIndex, seekTo: 0, autoPlay: true)
  }

  func trackAndOffset(for time: TimeInterval) -> (Int, TimeInterval) {
    guard !tracks.isEmpty else { return (0, time) }

    let totalDuration = tracks.reduce(0) { $0 + $1.duration }
    let clampedTime = max(0, min(time, totalDuration))

    for (i, track) in tracks.enumerated() {
      let trackEnd = track.startOffset + track.duration
      if clampedTime < trackEnd || i == tracks.count - 1 {
        return (i, clampedTime - track.startOffset)
      }
    }

    return (0, 0)
  }
}

private extension AudioPlayer {
  func setupObservers() {
    player.publisher(for: \.timeControlStatus)
      .removeDuplicates()
      .sink { [weak self] status in
        guard let self else { return }
        switch status {
        case .paused:
          self.events.send(.stateChanged(.paused))
        case .playing:
          self.events.send(.stateChanged(.playing))
        case .waitingToPlayAtSpecifiedRate where player.status != .readyToPlay:
          self.events.send(.stateChanged(.buffering))
        default:
          break
        }
      }
      .store(in: &cancellables)
  }

  func observeItem(_ item: AVPlayerItem) {
    itemObservers.removeAll()

    item.publisher(for: \.status)
      .removeDuplicates()
      .sink { [weak self] status in
        guard let self else { return }
        switch status {
        case .readyToPlay:
          self.events.send(.stateChanged(.ready))
        case .failed:
          AppLogger.player.error("Player item failed: \(item.error?.localizedDescription ?? "Unknown")")
          self.events.send(.error(item.error))
        default:
          break
        }
      }
      .store(in: &itemObservers)

    NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
      .sink { [weak self] _ in
        self?.advanceToNextTrack()
      }
      .store(in: &itemObservers)

    NotificationCenter.default.publisher(for: AVPlayerItem.playbackStalledNotification, object: item)
      .sink { [weak self] _ in
        AppLogger.player.warning("Playback stalled")
        self?.events.send(.stalled)
      }
      .store(in: &itemObservers)

    NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
      .sink { [weak self] notification in
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        AppLogger.player.error("Failed to play to end: \(error?.localizedDescription ?? "Unknown")")
        self?.events.send(.stalled)
      }
      .store(in: &itemObservers)

    NotificationCenter.default.publisher(for: AVPlayerItem.newErrorLogEntryNotification, object: item)
      .sink { _ in
        guard let entry = item.errorLog()?.events.last else { return }
        AppLogger.player.error("Player error log: \(entry.errorStatusCode) - \(entry.errorComment ?? "")")
      }
      .store(in: &itemObservers)
  }

  func addTimeObserver() {
    removeTimeObserver()
    let interval = CMTime(seconds: 0.5, preferredTimescale: 1000)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
      guard let self, !self.isPrepared else { return }
      self.events.send(.timeUpdate(self.time))
    }
  }

  func removeTimeObserver() {
    if let observer = timeObserver {
      player.removeTimeObserver(observer)
      timeObserver = nil
    }
  }
}

private extension AVPlayer {
  var currentSeconds: TimeInterval {
    currentTime().seconds.isNaN ? 0 : currentTime().seconds
  }
}
