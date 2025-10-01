import AVFoundation
import Audiobookshelf
import Combine
import Foundation
import MediaPlayer
import Models

final class BookPlayerModel: ObservableObject {
  let id: String
  let title: String
  let author: String?
  let coverURL: URL?

  @Published var isPlaying: Bool = false
  @Published var isLoading: Bool = false
  @Published var progress: Double = 0
  @Published var current: Double = 0
  @Published var remaining: Double = 0
  @Published var total: Double = 0
  @Published var totalTimeRemaining: Double = 0

  private let audiobookshelf = Audiobookshelf.shared

  private var player: AVPlayer?
  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  private var item: RecentlyPlayedItem?
  private var mediaProgress: MediaProgress
  private var timerSecondsCounter = 0

  private var lastPlaybackAt: Date?
  private var lastSyncAt = Date()

  init(_ item: RecentlyPlayedItem) {
    self.item = item
    self.id = item.bookID
    self.title = item.title
    self.author = item.author
    self.coverURL = item.coverURL

    do {
      self.mediaProgress = try MediaProgress.getOrCreate(for: item.bookID)
    } catch {
      fatalError("Failed to create MediaProgress for item \(item.bookID): \(error)")
    }

    onLoad()
  }

  func onTogglePlaybackTapped() {
    guard let player = player else { return }

    if isPlaying {
      player.rate = 0
    } else {
      player.rate = 1.0
    }
  }

  func onSkipForwardTapped() {
    guard let player = player else { return }
    let currentTime = player.currentTime()
    let newTime = CMTimeAdd(currentTime, CMTime(seconds: 30, preferredTimescale: 1))
    player.seek(to: newTime)
  }

  func onSkipBackwardTapped() {
    guard let player = player else { return }
    let currentTime = player.currentTime()
    let newTime = CMTimeSubtract(currentTime, CMTime(seconds: 30, preferredTimescale: 1))
    let zeroTime = CMTime(seconds: 0, preferredTimescale: 1)
    player.seek(to: CMTimeMaximum(newTime, zeroTime))
  }
}

extension BookPlayerModel {
  private func setupSessionInfo() async throws -> PlaySessionInfo {
    var sessionInfo: PlaySessionInfo?

    do {
      print("Attempting to fetch fresh session from server...")

      let audiobookshelfSession: PlaySession
      audiobookshelfSession = try await audiobookshelf.sessions.start(
        itemID: id,
        forceTranscode: false
      )

      let newPlaySessionInfo = PlaySessionInfo(from: audiobookshelfSession)

      if audiobookshelfSession.currentTime > mediaProgress.currentTime {
        mediaProgress.currentTime = audiobookshelfSession.currentTime
        print(
          "Using server currentTime for cross-device sync: \(audiobookshelfSession.currentTime)s")
      }

      if let item {
        item.playSessionInfo.merge(with: newPlaySessionInfo)
        try? MediaProgress.updateProgress(
          for: item.bookID,
          currentTime: mediaProgress.currentTime,
          timeListened: mediaProgress.timeListened,
          duration: item.playSessionInfo.duration,
          progress: mediaProgress.currentTime / item.playSessionInfo.duration
        )
        sessionInfo = item.playSessionInfo
        print("Merged fresh session with existing session")
      } else {
        let newItem = createRecentlyPlayedItem(for: newPlaySessionInfo)
        item = newItem
        sessionInfo = newPlaySessionInfo
      }

      print("Successfully fetched fresh session from server")

    } catch {
      print("Failed to fetch fresh session: \(error)")
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Cannot play without network connection")
    }

    guard let sessionInfo = sessionInfo else {
      throw Audiobookshelf.AudiobookshelfError.networkError("Failed to obtain session info")
    }

    return sessionInfo
  }

  private func setupAudioPlayer(sessionInfo: PlaySessionInfo) async throws -> AVPlayer {
    guard let serverURL = audiobookshelf.authentication.serverURL else {
      print("No server URL available")
      isLoading = false
      PlayerManager.shared.clearCurrent()
      throw Audiobookshelf.AudiobookshelfError.networkError("No server URL available")
    }

    guard
      let streamingURL = sessionInfo.streamingURL(
        at: mediaProgress.currentTime, serverURL: serverURL)
    else {
      print("Failed to get streaming URL")
      isLoading = false
      PlayerManager.shared.clearCurrent()
      throw Audiobookshelf.AudiobookshelfError.networkError("Failed to get streaming URL")
    }

    let playerItem = AVPlayerItem(url: streamingURL)
    let player = AVPlayer(playerItem: playerItem)
    self.player = player

    return player
  }

  private func configurePlayerComponents(player: AVPlayer, sessionInfo: PlaySessionInfo) {
    configureAudioSession()
    setupRemoteCommandCenter()
    setupPlayerObservers()
    setupTimeObserver()

    total = sessionInfo.duration
    updateNowPlayingInfo()
  }

  private func seekToLastPosition(player: AVPlayer) {
    if mediaProgress.currentTime > 0 {
      let seekTime = CMTime(seconds: mediaProgress.currentTime, preferredTimescale: 1000)
      let currentTime = mediaProgress.currentTime
      player.seek(to: seekTime) { _ in
        print("Seeked to previously played position: \(currentTime)s")
      }
    }
  }

  private func handleLoadError(_ error: Error) {
    print("Failed to setup player: \(error)")
    isLoading = false
    PlayerManager.shared.clearCurrent()
  }

  private func onLoad() {
    Task {
      isLoading = true

      do {
        let sessionInfo = try await setupSessionInfo()
        let player = try await setupAudioPlayer(sessionInfo: sessionInfo)
        configurePlayerComponents(player: player, sessionInfo: sessionInfo)
        seekToLastPosition(player: player)
        saveRecentlyPlayedItem()

        isLoading = false
      } catch {
        handleLoadError(error)
      }
    }
  }
}

extension BookPlayerModel {
  private func configureAudioSession() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .spokenAudio)

      if !audioSession.isOtherAudioPlaying {
        try audioSession.setActive(true)
      }
    } catch {
      print("Failed to configure audio session: \(error)")
    }
  }

  private func setupRemoteCommandCenter() {
    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.onTogglePlaybackTapped()
      return .success
    }

    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.onTogglePlaybackTapped()
      return .success
    }

    commandCenter.skipForwardCommand.addTarget { [weak self] _ in
      self?.onSkipForwardTapped()
      return .success
    }

    commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
      self?.onSkipBackwardTapped()
      return .success
    }

    commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 30)]
    commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 30)]

    updateNowPlayingInfo()
  }

  private func updateNowPlayingInfo() {
    var nowPlayingInfo = [String: Any]()
    nowPlayingInfo[MPMediaItemPropertyTitle] = title
    nowPlayingInfo[MPMediaItemPropertyArtist] = author

    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = total

    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = current
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  private func setupPlayerObservers() {
    guard let player = player else { return }

    player.publisher(for: \.rate)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] rate in
        self?.handlePlaybackStateChange(rate > 0)
        self?.isPlaying = rate > 0
        self?.updateNowPlayingInfo()
      }
      .store(in: &cancellables)

    if let currentItem = player.currentItem {
      currentItem.publisher(for: \.status)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] status in
          switch status {
          case .readyToPlay:
            self?.isLoading = false
          case .failed:
            self?.isLoading = false
            let errorMessage = currentItem.error?.localizedDescription ?? "Unknown error"
            print("Player item failed: \(errorMessage)")
            PlayerManager.shared.clearCurrent()
          case .unknown:
            self?.isLoading = true
          @unknown default:
            break
          }
        }
        .store(in: &cancellables)
    }
  }

  private func setupTimeObserver() {
    guard let player = player else { return }

    let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    let backgroundQueue = DispatchQueue(label: "timeObserver", qos: .userInitiated)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: backgroundQueue) {
      [weak self] time in
      guard let self else { return }

      if time.isValid && !time.isIndefinite {
        let currentTime = CMTimeGetSeconds(time)
        self.mediaProgress.currentTime = currentTime

        DispatchQueue.main.async {
          self.current = currentTime
          self.remaining = max(0, self.total - currentTime)
          self.progress = self.total > 0 ? currentTime / self.total : 0
          self.totalTimeRemaining = self.remaining
        }

        self.timerSecondsCounter += 1

        if self.timerSecondsCounter % 20 == 0 {
          self.updateRecentlyPlayedProgress()
        }

        DispatchQueue.main.async {
          self.updateNowPlayingInfo()
        }
      }
    }
  }

  private func createRecentlyPlayedItem(for sessionInfo: PlaySessionInfo) -> RecentlyPlayedItem {
    return RecentlyPlayedItem(
      bookID: id,
      title: title,
      author: author,
      coverURL: coverURL,
      playSessionInfo: sessionInfo
    )
  }

  private func saveRecentlyPlayedItem() {
    guard let sessionInfo = item?.playSessionInfo else {
      return
    }

    let newItem = createRecentlyPlayedItem(for: sessionInfo)

    do {
      try newItem.save()
      if let existingItem = try RecentlyPlayedItem.fetch(bookID: id) {
        self.item = existingItem
      } else {
        self.item = newItem
      }
    } catch {
      print("Failed to save recently played item: \(error)")
    }
  }

  private func handlePlaybackStateChange(_ isNowPlaying: Bool) {
    let now = Date()

    if isNowPlaying && !isPlaying {
      lastPlaybackAt = now
      mediaProgress.lastPlayedAt = Date()
    } else if !isNowPlaying && isPlaying {
      if let last = lastPlaybackAt {
        let timeListened = now.timeIntervalSince(last)
        mediaProgress.timeListened += timeListened
        syncSessionProgress()
      }
      lastPlaybackAt = nil
    }
    try? mediaProgress.save()
  }

  private func syncSessionProgress() {
    guard let sessionInfo = item?.playSessionInfo else { return }

    let now = Date()

    guard mediaProgress.timeListened >= 20, now.timeIntervalSince(lastSyncAt) >= 10 else { return }

    lastSyncAt = now

    Task {
      do {
        try await audiobookshelf.sessions.sync(
          sessionInfo.id,
          timeListened: mediaProgress.timeListened,
          currentTime: mediaProgress.currentTime
        )

        mediaProgress.timeListened = 0
      } catch {
        print("Failed to sync session progress: \(error)")
      }
    }
  }

  private func updateRecentlyPlayedProgress() {
    guard let item else { return }

    Task { @MainActor in
      do {
        if isPlaying, let lastTime = lastPlaybackAt {
          let timeListened = Date().timeIntervalSince(lastTime)
          mediaProgress.timeListened += timeListened
          lastPlaybackAt = Date()
        }

        mediaProgress.lastPlayedAt = Date()
        mediaProgress.lastUpdate = Date()
        if mediaProgress.duration > 0 {
          mediaProgress.progress = mediaProgress.currentTime / mediaProgress.duration
        }
        try mediaProgress.save()
        try item.save()

        syncSessionProgress()
      } catch {
        print("Failed to update recently played progress: \(error)")
      }
    }
  }

  func closeSession() {
    guard let sessionInfo = item?.playSessionInfo else {
      print("Session already closed or no session to close")
      return
    }

    Task {
      if mediaProgress.timeListened > 0 {
        do {
          try await audiobookshelf.sessions.sync(
            sessionInfo.id,
            timeListened: mediaProgress.timeListened,
            currentTime: mediaProgress.currentTime
          )

          mediaProgress.timeListened = 0
        } catch {
          print("Failed to sync session progress: \(error)")
        }
      }

      do {
        try await audiobookshelf.sessions.close(sessionInfo.id)
        print("Successfully closed session: \(sessionInfo.id)")
      } catch {
        print("Failed to close session: \(error)")
      }
    }
  }
}
