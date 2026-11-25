import API
import Combine
import Foundation
import Models

enum CastEvent {
  case sessionStarted
  case sessionEnded
  case positionUpdated(index: Int, position: TimeInterval)
  case stateChanged(isPlaying: Bool)
  case finished
  case error
}

protocol CastClientProtocol: AnyObject {
  var events: PassthroughSubject<CastEvent, Never> { get }
  var hasMedia: Bool { get }
  func load(
    streams: [(url: URL, contentType: String)],
    startIndex: Int,
    startTime: TimeInterval,
    title: String,
    author: String?,
    coverURL: URL?,
    playbackRate: Float,
    autoplay: Bool
  )
  func play()
  func pause()
  func seek(to time: TimeInterval)
  func setRate(_ rate: Float)
}

final class CastPlaybackController {
  static var isConnected: Bool {
    #if !targetEnvironment(macCatalyst)
    CastManager.shared.isConnected
    #else
    false
    #endif
  }

  let events = PassthroughSubject<AudioPlayer.Event, Never>()

  private(set) var isPlaying = false
  private(set) var time: TimeInterval?

  var isPlaybackActive: Bool { isPlaying || wantsPlayback }

  private let client: CastClientProtocol?
  private var session: PlaybackSession?
  private var tracks: [Track] { session?.tracks ?? [] }
  private var currentTrackIndex = 0
  private var rate: Float = 1
  private var wantsPlayback = false
  private var cancellables = Set<AnyCancellable>()

  init() {
    #if !targetEnvironment(macCatalyst)
    client = CastManager.shared
    #else
    client = nil
    #endif

    client?.events
      .sink { [weak self] event in
        self?.handle(event)
      }
      .store(in: &cancellables)
  }

  func load(session: PlaybackSession, at time: TimeInterval, rate: Float, autoPlay: Bool) {
    self.session = session
    self.rate = min(rate, 2)

    let (index, offset) = tracks.trackAndOffset(for: time)
    loadQueue(from: index, offset: offset, autoPlay: autoPlay)
  }

  func play(at position: TimeInterval) {
    guard client?.hasMedia == true else {
      let (index, offset) = tracks.trackAndOffset(for: position)
      loadQueue(from: index, offset: offset, autoPlay: true)
      return
    }
    wantsPlayback = true
    client?.play()
  }

  func pause() {
    wantsPlayback = false
    client?.pause()
    if !isPlaying {
      events.send(.stateChanged(.paused))
    }
  }

  func seek(to time: TimeInterval) {
    let (index, offset) = tracks.trackAndOffset(for: time)
    events.send(.seek(time))

    guard index == currentTrackIndex else {
      loadQueue(from: index, offset: offset, autoPlay: wantsPlayback)
      return
    }

    self.time = time
    client?.seek(to: offset)
  }

  func setRate(_ rate: Float) {
    self.rate = min(rate, 2)
    client?.setRate(self.rate)
  }
}

private extension CastPlaybackController {
  func loadQueue(from index: Int, offset: TimeInterval, autoPlay: Bool) {
    let urls = tracks.compactMap { session?.remoteURL(for: $0) }
    guard let session, urls.count == tracks.count, tracks.indices.contains(index) else {
      events.send(.error(nil))
      return
    }

    currentTrackIndex = index
    wantsPlayback = autoPlay
    time = tracks[index].startOffset + offset

    client?.load(
      streams: zip(urls, tracks).map { (url: $0, contentType: $1.mimeType ?? "audio/mpeg") },
      startIndex: index,
      startTime: offset,
      title: session.displayTitle ?? "Audiobook",
      author: session.displayAuthor,
      coverURL: Audiobookshelf.shared.authentication.serverURL?
        .appendingPathComponent("api/items/\(session.libraryItemID)/cover"),
      playbackRate: rate,
      autoplay: autoPlay
    )
  }

  func handle(_ event: CastEvent) {
    switch event {
    case .sessionStarted:
      events.send(.castSessionChanged)

    case .sessionEnded:
      isPlaying = false
      wantsPlayback = false
      time = nil
      events.send(.stateChanged(.paused))
      events.send(.castSessionChanged)

    case .positionUpdated(let index, let position):
      guard tracks.indices.contains(index) else { return }
      currentTrackIndex = index
      let track = tracks[index]
      let time = track.startOffset + min(max(0, position), track.duration)
      self.time = time
      events.send(.timeUpdate(time))

    case .stateChanged(let isNowPlaying):
      isPlaying = isNowPlaying
      wantsPlayback = isNowPlaying
      events.send(.stateChanged(isNowPlaying ? .playing : .paused))

    case .finished:
      isPlaying = false
      events.send(.finished)

    case .error:
      isPlaying = false
      events.send(.error(nil))
    }
  }
}
