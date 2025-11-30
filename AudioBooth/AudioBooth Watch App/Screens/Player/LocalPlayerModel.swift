import API
import AVFoundation
import Combine
import Foundation
import MediaPlayer
import Models
import OSLog
import WatchConnectivity

final class LocalPlayerModel: PlayerView.Model {
  var currentChapterIndex: Int = 0

  private let audiobookshelf = Audiobookshelf.shared
  private let downloadManager = DownloadManager.shared
  private let connectivityManager = WatchConnectivityManager.shared

  private var player: AVPlayer?
  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  var item: LocalBook
  private var session: Session?
  private var mediaProgress: MediaProgress
  private var timerSecondsCounter = 0
  private var chaptersList: [Models.Chapter] = []
  private var total: Double = 0
  private var hasStartedPlayback: Bool = false

  private var lastPlaybackAt: Date?
  private var lastSyncAt = Date()
  private var timeSinceLastSync: TimeInterval = 0

  private var itemObservation: Task<Void, Never>?

  private class LocalPlayerOptionsModel: PlayerOptionsSheet.Model {
    weak var playerModel: LocalPlayerModel?

    override func onChaptersTapped() {
      playerModel?.chapters?.isPresented = true
    }

    override func onDownloadTapped() {
      playerModel?.onDownloadTapped()
    }
  }

  private class LocalPlayerPlaybackDestinationModel: PlaybackDestinationSheet.Model {
    weak var playerModel: LocalPlayerModel?

    override func onPlayOnWatch() {
      playerModel?.playOnWatch()
    }

    override func onPlayOnIPhone() {
      playerModel?.playOnIPhone()
    }
  }

  init?(_ item: LocalBook) {
    self.item = item

    do {
      self.mediaProgress = try MediaProgress.getOrCreate(for: item.bookID, duration: item.duration)
    } catch {
      AppLogger.player.error(
        "Failed to create MediaProgress for item \(item.bookID, privacy: .public): \(error, privacy: .public)"
      )
      return nil
    }

    super.init(
      isPlaying: false,
      progress: 0,
      current: 0,
      remaining: 0,
      totalTimeRemaining: 0,
      title: item.title,
      author: item.authorNames,
      coverURL: item.coverURL
    )

    setupDownloadStateBinding()
    setupInitialChapters()
    setupOptionsModel()
    onLoad()
  }

  init?(_ book: Book) {
    let existingItem = try? LocalBook.fetch(bookID: book.id)
    self.item = existingItem ?? LocalBook(from: book)

    do {
      self.mediaProgress = try MediaProgress.getOrCreate(for: book.id, duration: item.duration)
    } catch {
      AppLogger.player.error(
        "Failed to create MediaProgress for book \(book.id, privacy: .public): \(error, privacy: .public)"
      )
      return nil
    }

    super.init(
      isPlaying: false,
      progress: 0,
      current: 0,
      remaining: 0,
      totalTimeRemaining: 0,
      title: book.title,
      author: book.authorName ?? "",
      coverURL: book.coverURL
    )

    setupDownloadStateBinding()
    setupInitialChapters()
    setupOptionsModel()
    onLoad()
  }

  private func setupInitialChapters() {
    let sessionChapters = item.orderedChapters
    guard !sessionChapters.isEmpty else {
      return
    }

    chaptersList = sessionChapters
    currentChapterIndex = 0
    total = item.duration
  }

  private func setupChapters(player: AVPlayer) {
    guard !chaptersList.isEmpty else { return }

    chapters = ChapterPickerSheetViewModel(
      chapters: chaptersList,
      player: player,
      currentIndex: currentChapterIndex
    )
  }

  private func setupOptionsModel() {
    let optionsModel = LocalPlayerOptionsModel(
      hasChapters: chapters != nil,
      downloadState: .notDownloaded
    )
    optionsModel.playerModel = self
    options = optionsModel
  }

  override func togglePlayback() {
    guard let player else { return }

    if !hasStartedPlayback && !isPlaying {
      if WCSession.default.isReachable {
        let destinationModel = LocalPlayerPlaybackDestinationModel()
        destinationModel.playerModel = self
        playbackDestination = destinationModel
        return
      }
    }

    if isPlaying {
      player.rate = 0
    } else {
      hasStartedPlayback = true
      player.rate = 1.0
    }
  }

  private func playOnWatch() {
    guard let player else { return }
    hasStartedPlayback = true
    playbackDestination = nil
    player.rate = 1.0
  }

  private func playOnIPhone() {
    playbackDestination = nil
    connectivityManager.playBook(bookID: item.bookID)

    Task { @MainActor in
      PlayerManager.shared.clearCurrent()
      PlayerManager.shared.isShowingFullPlayer = false
      try? await Task.sleep(for: .milliseconds(100))
      PlayerManager.shared.current = RemotePlayerModel()
      PlayerManager.shared.isShowingFullPlayer = true
    }
  }

  override func skipForward() {
    guard let player else { return }
    let currentTime = player.currentTime()
    let newTime = CMTimeAdd(currentTime, CMTime(seconds: 30, preferredTimescale: 1))
    player.seek(to: newTime)
  }

  override func skipBackward() {
    guard let player else { return }
    let currentTime = player.currentTime()
    let newTime = CMTimeSubtract(currentTime, CMTime(seconds: 30, preferredTimescale: 1))
    let zeroTime = CMTime(seconds: 0, preferredTimescale: 1)
    player.seek(to: CMTimeMaximum(newTime, zeroTime))
  }

  func seekToChapter(at index: Int) {
    guard let player, !chaptersList.isEmpty, index >= 0, index < chaptersList.count else {
      return
    }
    let chapter = chaptersList[index]
    player.seek(to: CMTime(seconds: chapter.start + 0.1, preferredTimescale: 1000))
  }

  override func onDownloadTapped() {
    switch options.downloadState {
    case .downloading:
      downloadManager.cancelDownload(for: item.bookID)
      options.downloadState = .notDownloaded

    case .downloaded:
      downloadManager.deleteDownload(for: item.bookID)
      options.downloadState = .notDownloaded

    case .notDownloaded:
      downloadManager.startDownload(for: item)
      options.downloadState = .downloading(progress: 0)
    }
  }

  private func setupDownloadStateBinding() {
    downloadManager.$currentProgress
      .receive(on: DispatchQueue.main)
      .map { [weak self] progressDict in
        guard let item = self?.item else { return .notDownloaded }

        if let progress = progressDict[item.bookID] {
          return .downloading(progress: progress)
        }

        return item.isDownloaded ? .downloaded : .notDownloaded
      }
      .sink { [weak self] downloadState in
        self?.options.downloadState = downloadState
      }
      .store(in: &cancellables)

    let bookID = item.bookID
    itemObservation = Task { [weak self] in
      for await updatedItem in LocalBook.observe(where: \.bookID, equals: bookID) {
        guard !Task.isCancelled, let self else { continue }

        self.item = updatedItem

        self.options.downloadState = item.isDownloaded ? .downloaded : .notDownloaded
      }
    }
  }
}

extension LocalPlayerModel {
  private func setupSessionInfo() async throws {
    // If book is already downloaded, use local files (session is optional)
    if item.isDownloaded {
      AppLogger.player.info("Book is downloaded, using local files (session optional)")
      AppLogger.player.debug("Item has \(self.item.tracks.count, privacy: .public) tracks")

      // Try to fetch session for streaming URLs, but don't fail if it doesn't work
      do {
        AppLogger.player.debug("Attempting to fetch session for potential streaming...")
        let audiobookshelfSession = try await audiobookshelf.sessions.start(
          itemID: item.bookID,
          forceTranscode: false
        )
        self.session = Session(from: audiobookshelfSession)

        if audiobookshelfSession.currentTime > mediaProgress.currentTime {
          mediaProgress.currentTime = audiobookshelfSession.currentTime
          AppLogger.player.info(
            "Using server currentTime for cross-device sync: \(audiobookshelfSession.currentTime, privacy: .public)s"
          )
        }

        AppLogger.player.info("Session available for streaming if needed")
      } catch {
        AppLogger.player.warning(
          "Session fetch failed, will use local files only: \(error, privacy: .public)")
      }

      return
    }

    // Book is not downloaded, session is required
    do {
      AppLogger.player.info("Attempting to fetch fresh session from server...")

      let audiobookshelfSession: PlaySession
      audiobookshelfSession = try await audiobookshelf.sessions.start(
        itemID: item.bookID,
        forceTranscode: false
      )

      if audiobookshelfSession.currentTime > mediaProgress.currentTime {
        mediaProgress.currentTime = audiobookshelfSession.currentTime
        AppLogger.player.info(
          "Using server currentTime for cross-device sync: \(audiobookshelfSession.currentTime, privacy: .public)s"
        )
      }

      self.session = Session(from: audiobookshelfSession)
      item.duration = audiobookshelfSession.duration

      guard let newTracks = audiobookshelfSession.streamingTracks?.map(Track.init) else {
        item.tracks = []
        throw Audiobookshelf.AudiobookshelfError.networkError("No tracks available")
      }

      var mergedTracks: [Track] = []
      for newTrack in newTracks {
        if let existingTrack = item.tracks.first(where: { $0.index == newTrack.index }) {
          newTrack.relativePath = existingTrack.relativePath
        }
        mergedTracks.append(newTrack)
      }
      item.tracks = mergedTracks
      item.chapters = audiobookshelfSession.chapters?.map(Chapter.init) ?? []

      try? MediaProgress.updateProgress(
        for: item.bookID,
        currentTime: mediaProgress.currentTime,
        duration: item.duration,
        progress: mediaProgress.currentTime / item.duration
      )
      AppLogger.player.debug("Merged fresh session with existing session")

      AppLogger.player.info("Successfully fetched fresh session from server")

    } catch {
      AppLogger.player.error("Failed to fetch fresh session: \(error, privacy: .public)")
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Cannot play without network connection or downloaded files")
    }
  }

  private func setupAudioPlayer() async throws -> AVPlayer {
    guard let track = item.track(at: mediaProgress.currentTime) else {
      AppLogger.player.error(
        "Failed to get track at time \(self.mediaProgress.currentTime, privacy: .public)")
      isLoading = false
      PlayerManager.shared.clearCurrent()
      throw Audiobookshelf.AudiobookshelfError.networkError("Failed to get track")
    }

    let trackURL = session?.url(for: track) ?? track.localPath
    guard let trackURL else {
      AppLogger.player.error("No URL available for track")
      isLoading = false
      PlayerManager.shared.clearCurrent()
      throw Audiobookshelf.AudiobookshelfError.networkError("Failed to get track URL")
    }

    let playerItem = AVPlayerItem(url: trackURL)
    let player = AVPlayer(playerItem: playerItem)
    self.player = player

    return player
  }

  private func configurePlayerComponents(player: AVPlayer) {
    configureAudioSession()
    setupRemoteCommandCenter()
    setupPlayerObservers()
    setupTimeObserver()
    setupChapters(player: player)

    total = item.duration

    let sessionChapters = item.orderedChapters
    if !sessionChapters.isEmpty {
      chaptersList = sessionChapters
      currentChapterIndex = 0
      setupChapters(player: player)
      options.hasChapters = true
    }

    updateNowPlayingInfo()
  }

  private func seekToLastPosition(player: AVPlayer) {
    if mediaProgress.currentTime > 0 {
      let seekTime = CMTime(seconds: mediaProgress.currentTime, preferredTimescale: 1000)
      let currentTime = mediaProgress.currentTime
      player.seek(to: seekTime) { _ in
        AppLogger.player.debug(
          "Seeked to previously played position: \(currentTime, privacy: .public)s")
      }
    }
  }

  private func handleLoadError(_ error: Error) {
    AppLogger.player.error("Failed to setup player: \(error, privacy: .public)")
    isLoading = false
    PlayerManager.shared.clearCurrent()
  }

  private func onLoad() {
    Task {
      isLoading = true

      do {
        try await setupSessionInfo()
        let player = try await setupAudioPlayer()
        configurePlayerComponents(player: player)
        seekToLastPosition(player: player)

        isLoading = false
      } catch {
        handleLoadError(error)
      }
    }
  }
}

extension LocalPlayerModel {
  private func configureAudioSession() {
    Task {
      do {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
          .playback,
          mode: .spokenAudio,
          policy: .longFormAudio,
          options: []
        )

        try await audioSession.activate()
      } catch {
        AppLogger.player.error("Failed to configure audio session: \(error, privacy: .public)")
      }
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

    commandCenter.skipForwardCommand.addTarget { [weak self] event in
      guard let self else { return .commandFailed }

      let interval: Double
      if let skipEvent = event as? MPSkipIntervalCommandEvent, skipEvent.interval > 0 {
        interval = skipEvent.interval
      } else {
        interval = 30
      }

      let currentTime = self.player?.currentTime() ?? .zero
      let newTime = CMTimeAdd(currentTime, CMTime(seconds: interval, preferredTimescale: 1))
      self.player?.seek(to: newTime)
      return .success
    }

    commandCenter.skipBackwardCommand.addTarget { [weak self] event in
      guard let self else { return .commandFailed }

      let interval: Double
      if let skipEvent = event as? MPSkipIntervalCommandEvent, skipEvent.interval > 0 {
        interval = skipEvent.interval
      } else {
        interval = 30
      }

      let currentTime = self.player?.currentTime() ?? .zero
      let newTime = CMTimeSubtract(currentTime, CMTime(seconds: interval, preferredTimescale: 1))
      let zeroTime = CMTime(seconds: 0, preferredTimescale: 1)
      self.player?.seek(to: CMTimeMaximum(newTime, zeroTime))
      return .success
    }

    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      self?.skipForward()
      return .success
    }

    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      self?.skipBackward()
      return .success
    }

    commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 30)]
    commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 30)]

    commandCenter.skipForwardCommand.isEnabled = true
    commandCenter.skipBackwardCommand.isEnabled = true
    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.isEnabled = true

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
    guard let player else { return }

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
            self?.isReadyToPlay = true
          case .failed:
            self?.isLoading = false
            self?.isReadyToPlay = false
            let errorMessage = currentItem.error?.localizedDescription ?? "Unknown error"
            AppLogger.player.error("Player item failed: \(errorMessage, privacy: .public)")
            PlayerManager.shared.clearCurrent()
          case .unknown:
            self?.isLoading = true
            self?.isReadyToPlay = false
          @unknown default:
            break
          }
        }
        .store(in: &cancellables)
    }

    NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] notification in
        self?.handleAudioInterruption(notification)
      }
      .store(in: &cancellables)

    NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.handleMediaServicesReset()
      }
      .store(in: &cancellables)
  }

  private func handleAudioInterruption(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else {
      return
    }

    switch type {
    case .began:
      AppLogger.player.debug("Audio interruption began")

    case .ended:
      guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
        return
      }

      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      if options.contains(.shouldResume) {
        AppLogger.player.debug("Audio interruption ended - resuming playback")
        player?.rate = 1.0
      } else {
        AppLogger.player.debug("Audio interruption ended - not resuming")
      }

    @unknown default:
      break
    }
  }

  private func handleMediaServicesReset() {
    AppLogger.player.warning(
      "Media services were reset - reconfiguring audio session and remote commands")

    configureAudioSession()
    setupRemoteCommandCenter()
  }

  private func setupTimeObserver() {
    guard let player else { return }

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
          self.updateMediaProgress()
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

  private func handlePlaybackStateChange(_ isNowPlaying: Bool) {
    let now = Date()

    if isNowPlaying && !isPlaying {
      lastPlaybackAt = now
      mediaProgress.lastPlayedAt = Date()
    } else if !isNowPlaying && isPlaying {
      if let last = lastPlaybackAt {
        let timeListened = now.timeIntervalSince(last)
        timeSinceLastSync += timeListened
        syncSessionProgress()
      }
      lastPlaybackAt = nil
    }

    try? mediaProgress.save()
    try? item.save()
  }

  private func syncSessionProgress() {
    guard let session = self.session else { return }

    let now = Date()

    guard timeSinceLastSync >= 20, now.timeIntervalSince(lastSyncAt) >= 10 else { return }

    lastSyncAt = now

    Task {
      do {
        try await audiobookshelf.sessions.sync(
          session.id,
          timeListened: timeSinceLastSync,
          currentTime: mediaProgress.currentTime
        )

        timeSinceLastSync = 0
      } catch {
        AppLogger.player.error("Failed to sync session progress: \(error, privacy: .public)")
      }
    }
  }

  private func updateMediaProgress() {
    Task { @MainActor in
      do {
        if isPlaying, let lastTime = lastPlaybackAt {
          let timeListened = Date().timeIntervalSince(lastTime)
          timeSinceLastSync += timeListened
          lastPlaybackAt = Date()
        }

        mediaProgress.lastPlayedAt = Date()
        mediaProgress.lastUpdate = Date()
        if mediaProgress.duration > 0 {
          mediaProgress.progress = mediaProgress.currentTime / mediaProgress.duration
        }
        try mediaProgress.save()

        syncSessionProgress()
      } catch {
        AppLogger.player.error("Failed to update played progress: \(error, privacy: .public)")
      }
    }
  }
}
