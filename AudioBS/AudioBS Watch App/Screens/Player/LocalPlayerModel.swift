import AVFoundation
import Audiobookshelf
import Combine
import Foundation
import MediaPlayer
import Models

final class LocalPlayerModel: PlayerView.Model {
  var currentChapterIndex: Int = 0

  private let audiobookshelf = Audiobookshelf.shared
  private let downloadManager = DownloadManager.shared

  private var player: AVPlayer?
  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  var item: RecentlyPlayedItem
  private var mediaProgress: MediaProgress
  private var timerSecondsCounter = 0
  private var chaptersList: [ChapterInfo] = []
  private var total: Double = 0

  private var lastPlaybackAt: Date?
  private var lastSyncAt = Date()

  private class LocalChapterPickerModel: ChapterPickerSheet.Model {
    weak var playerModel: LocalPlayerModel?

    override func onChapterTapped(at index: Int) {
      playerModel?.seekToChapter(at: index)
    }
  }

  private class LocalPlayerOptionsModel: PlayerOptionsSheet.Model {
    weak var playerModel: LocalPlayerModel?

    override func onChaptersTapped() {
      playerModel?.chapters?.isPresented = true
    }

    override func onDownloadTapped() {
      playerModel?.onDownloadTapped()
    }
  }

  init(_ item: RecentlyPlayedItem) {
    self.item = item

    do {
      self.mediaProgress = try MediaProgress.getOrCreate(for: item.bookID)
    } catch {
      fatalError("Failed to create MediaProgress for item \(item.bookID): \(error)")
    }

    super.init(
      isPlaying: false,
      progress: 0,
      current: 0,
      remaining: 0,
      totalTimeRemaining: 0,
      title: item.title,
      author: item.author ?? "",
      coverURL: item.coverURL
    )

    setupDownloadStateBinding()
    setupOptionsModel()
    onLoad()
  }

  private func setupOptionsModel() {
    let optionsModel = LocalPlayerOptionsModel(
      hasChapters: chapters != nil,
      downloadState: downloadState
    )
    optionsModel.playerModel = self
    options = optionsModel
  }

  override func togglePlayback() {
    guard let player = player else { return }

    if isPlaying {
      player.rate = 0
    } else {
      player.rate = 1.0
    }
  }

  override func skipForward() {
    guard let player = player else { return }
    let currentTime = player.currentTime()
    let newTime = CMTimeAdd(currentTime, CMTime(seconds: 30, preferredTimescale: 1))
    player.seek(to: newTime)
  }

  override func skipBackward() {
    guard let player = player else { return }
    let currentTime = player.currentTime()
    let newTime = CMTimeSubtract(currentTime, CMTime(seconds: 30, preferredTimescale: 1))
    let zeroTime = CMTime(seconds: 0, preferredTimescale: 1)
    player.seek(to: CMTimeMaximum(newTime, zeroTime))
  }

  func seekToChapter(at index: Int) {
    guard let player = player, !chaptersList.isEmpty, index >= 0, index < chaptersList.count else {
      return
    }
    let chapter = chaptersList[index]
    player.seek(to: CMTime(seconds: chapter.start + 0.1, preferredTimescale: 1000))
  }

  override func onDownloadTapped() {
    switch downloadState {
    case .downloading:
      downloadManager.cancelDownload(for: item.bookID)
    case .downloaded:
      downloadManager.deleteDownload(for: item.bookID)
    case .notDownloaded:
      downloadManager.startDownload(for: item)
    }
  }

  private func setupDownloadStateBinding() {
    downloadManager.$downloads
      .map { [weak self] downloads -> DownloadManager.DownloadState in
        guard let self = self else { return .notDownloaded }

        if downloads[item.bookID] == true {
          return .downloading
        }

        return item.playSessionInfo.isDownloaded ? .downloaded : .notDownloaded
      }
      .sink { [weak self] downloadState in
        self?.downloadState = downloadState
        self?.options.downloadState = downloadState
      }
      .store(in: &cancellables)
  }
}

extension LocalPlayerModel {
  private func setupSessionInfo() async throws -> PlaySessionInfo {
    if item.playSessionInfo.isDownloaded {
      print("Playing downloaded book offline")
      return item.playSessionInfo
    }

    var sessionInfo: PlaySessionInfo?

    do {
      print("Attempting to fetch fresh session from server...")

      let audiobookshelfSession: PlaySession
      audiobookshelfSession = try await audiobookshelf.sessions.start(
        itemID: item.bookID,
        forceTranscode: false
      )

      let newPlaySessionInfo = PlaySessionInfo(from: audiobookshelfSession)

      if audiobookshelfSession.currentTime > mediaProgress.currentTime {
        mediaProgress.currentTime = audiobookshelfSession.currentTime
        print(
          "Using server currentTime for cross-device sync: \(audiobookshelfSession.currentTime)s")
      }

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
    let streamingURL: URL?

    if sessionInfo.isDownloaded {
      streamingURL = sessionInfo.streamingURL(
        at: mediaProgress.currentTime, serverURL: URL(string: "http://localhost")!)
      print("Using local file URL for downloaded book")
    } else {
      guard let serverURL = audiobookshelf.authentication.serverURL else {
        print("No server URL available")
        isLoading = false
        PlayerManager.shared.clearCurrent()
        throw Audiobookshelf.AudiobookshelfError.networkError("No server URL available")
      }

      streamingURL = sessionInfo.streamingURL(at: mediaProgress.currentTime, serverURL: serverURL)
    }

    guard let streamingURL else {
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

    if let sessionChapters = sessionInfo.orderedChapters {
      chaptersList = sessionChapters
      if !chaptersList.isEmpty {
        currentChapterIndex = 0
        print("Loaded \(chaptersList.count) chapters")

        let pickerChapters = chaptersList.enumerated().map { index, chapter in
          ChapterPickerSheet.Model.Chapter(
            id: index,
            title: chapter.title,
            start: chapter.start,
            end: chapter.end
          )
        }
        let chapterPickerModel = LocalChapterPickerModel(
          chapters: pickerChapters,
          currentIndex: currentChapterIndex
        )
        chapterPickerModel.playerModel = self
        chapters = chapterPickerModel
        options.hasChapters = true
      }
    }

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

extension LocalPlayerModel {
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
      self?.togglePlayback()
      return .success
    }

    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.togglePlayback()
      return .success
    }

    commandCenter.skipForwardCommand.addTarget { [weak self] _ in
      self?.skipForward()
      return .success
    }

    commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
      self?.skipBackward()
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

          // Update chapter tracking
          self.updateCurrentChapter(currentTime: currentTime)
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

  private func updateCurrentChapter(currentTime: TimeInterval) {
    guard !chaptersList.isEmpty else { return }

    // Find current chapter
    for (index, chapter) in chaptersList.enumerated() {
      if currentTime >= chapter.start && currentTime < chapter.end {
        if currentChapterIndex != index {
          currentChapterIndex = index
          chapters?.currentIndex = index
        }

        // Calculate chapter progress
        let chapterDuration = chapter.end - chapter.start
        if chapterDuration > 0 {
          current = currentTime - chapter.start
          remaining = chapter.end - currentTime
          progress = current / chapterDuration
        }
        break
      }
    }
  }

  private func createRecentlyPlayedItem(for sessionInfo: PlaySessionInfo) -> RecentlyPlayedItem {
    return RecentlyPlayedItem(
      bookID: item.bookID,
      title: title,
      author: author.isEmpty ? nil : author,
      coverURL: coverURL,
      playSessionInfo: sessionInfo
    )
  }

  private func saveRecentlyPlayedItem() {
    let sessionInfo = item.playSessionInfo
    let newItem = createRecentlyPlayedItem(for: sessionInfo)

    do {
      try newItem.save()
      if let existingItem = try RecentlyPlayedItem.fetch(bookID: item.bookID) {
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
    let sessionInfo = item.playSessionInfo

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
    let sessionInfo = item.playSessionInfo

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
