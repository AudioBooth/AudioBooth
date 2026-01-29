import API
import AVFoundation
import AVKit
import Combine
import Logging
import MediaPlayer
import Models
import Nuke
import SwiftData
import SwiftUI
import WidgetKit

final class BookPlayerModel: BookPlayer.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let playerManager = PlayerManager.shared
  private let sessionManager = SessionManager.shared
  private let userPreferences = UserPreferences.shared

  private let audioSession = AVAudioSession.sharedInstance()
  private var player: AVPlayer?

  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  private var item: LocalBook?
  private var itemObservation: Task<Void, Never>?
  private var mediaProgress: MediaProgress
  private var timerSecondsCounter = 0
  private var pendingPlay: Bool = false
  private var pendingSeekTime: TimeInterval?

  private var lastPlaybackAt: Date?

  private let downloadManager = DownloadManager.shared
  private let watchConnectivity = WatchConnectivityManager.shared

  private var nowPlaying: NowPlayingManager

  private var recoveryAttempts = 0
  private var maxRecoveryAttempts = 3
  private var isRecovering = false
  private var interruptionBeganAt: Date?
  private var volumeObservation: NSKeyValueObservation?

  init(_ book: Book) {
    self.item = nil
    do {
      self.mediaProgress = try MediaProgress.getOrCreate(for: book.id, duration: book.duration)
    } catch {
      fatalError("Failed to create MediaProgress for book \(book.id): \(error)")
    }

    nowPlaying = NowPlayingManager(
      id: book.id,
      title: book.title,
      author: book.authorName,
      coverURL: book.coverURL(raw: true),
      current: mediaProgress.currentTime,
      duration: mediaProgress.duration
    )

    super.init(
      id: book.id,
      title: book.title,
      author: book.authorName,
      coverURL: book.coverURL(raw: true),
      speed: SpeedPickerSheet.Model(),
      timer: TimerPickerSheet.Model(),
      bookmarks: BookmarkViewerSheet.Model(),
      history: PlaybackHistorySheet.Model(),
      playbackProgress: PlaybackProgressViewModel(itemID: book.id, mediaProgress: mediaProgress, title: book.title)
    )

    setupDownloadStateBinding(bookID: book.id)
    setupHistory()
    observeSpeedChanged()
    observeVolumeLevelChanged()

    onLoad()
  }

  init(_ item: LocalBook) {
    self.item = item
    do {
      self.mediaProgress = try MediaProgress.getOrCreate(for: item.bookID, duration: item.duration)
    } catch {
      fatalError("Failed to create MediaProgress for item \(item.bookID): \(error)")
    }

    nowPlaying = NowPlayingManager(
      id: item.bookID,
      title: item.title,
      author: item.authorNames,
      coverURL: item.coverURL(raw: true),
      current: mediaProgress.currentTime,
      duration: mediaProgress.duration
    )

    super.init(
      id: item.bookID,
      title: item.title,
      author: item.authorNames,
      coverURL: item.coverURL(raw: true),
      speed: SpeedPickerSheet.Model(),
      timer: TimerPickerSheet.Model(),
      bookmarks: BookmarkViewerSheet.Model(),
      history: PlaybackHistorySheet.Model(),
      playbackProgress: PlaybackProgressViewModel(itemID: item.bookID, mediaProgress: mediaProgress, title: item.title)
    )

    setupDownloadStateBinding(bookID: item.bookID)
    setupHistory()
    observeSpeedChanged()
    observeVolumeLevelChanged()

    onLoad()
  }

  override func onTogglePlaybackTapped() {
    if isPlaying {
      onPauseTapped()
    } else {
      onPlayTapped()
    }
  }

  override func onPauseTapped() {
    pendingPlay = false
    interruptionBeganAt = nil
    player?.pause()
  }

  override func onPlayTapped() {
    if userPreferences.shakeSensitivity.isEnabled,
      let timer = timer as? TimerPickerSheetViewModel,
      let completedAlert = timer.completedAlert,
      !completedAlert.isExpired
    {
      completedAlert.onExtendTapped()
      return
    }

    guard let player, !isLoading else {
      pendingPlay = true
      return
    }

    if sessionManager.current == nil {
      AppLogger.player.warning("Session was closed, recreating and reloading player")

      Task {
        do {
          try await setupSession(forceTranscode: false)
          AppLogger.player.info("Session recreated successfully")

          if isPlayerUsingRemoteURL() {
            AppLogger.player.info("Player using remote URLs, reloading with new session")
            await reloadPlayer()
          } else {
            AppLogger.player.info("Player using local files, no reload needed")
          }
        } catch {
          AppLogger.player.error("Failed to recreate session: \(error)")
        }
      }
    }

    guard player.status == .readyToPlay else {
      if sessionManager.current != nil, !pendingPlay {
        AppLogger.player.warning("Player not ready (status: \(player.status.rawValue)), reloading")
        Task {
          await reloadPlayer()
        }
      }
      pendingPlay = true
      return
    }

    applySmartRewind(reason: .afterPause)

    timerSecondsCounter = 0
    player.play()
    try? audioSession.setActive(true)

    if let timerViewModel = timer as? TimerPickerSheetViewModel {
      timerViewModel.activateAutoTimerIfNeeded()
    }

    pendingPlay = false
  }

  override func onSkipForwardTapped(seconds: Double) {
    guard let player else { return }
    let currentTime = CMTimeGetSeconds(player.currentTime())
    let newTime = currentTime + seconds
    seekToTime(newTime)
  }

  override func onSkipBackwardTapped(seconds: Double) {
    guard let player else { return }
    let currentTime = CMTimeGetSeconds(player.currentTime())
    let newTime = max(0, currentTime - seconds)
    seekToTime(newTime)
  }

  override func onBookmarksTapped() {
    if let player {
      let time = player.currentTime()
      if time.isValid && !time.isIndefinite {
        bookmarks?.currentTime = Int(ceil(CMTimeGetSeconds(time)))
      }
    }
    bookmarks?.isPresented = true
  }

  func getCurrentTime() -> Int? {
    guard let player else { return nil }
    let time = player.currentTime()
    guard time.isValid && !time.isIndefinite else { return nil }
    return Int(ceil(CMTimeGetSeconds(time)))
  }

  override func onHistoryTapped() {
    history?.isPresented = true
  }

  override func onDownloadTapped() {
    guard let item else { return }

    switch downloadState {
    case .downloading:
      downloadState = .notDownloaded
      downloadManager.cancelDownload(for: id)

    case .downloaded:
      item.removeDownload()

    case .notDownloaded:
      downloadState = .downloading(progress: 0)
      try? item.download()
    }
  }
}

extension BookPlayerModel {
  func seekToTime(_ time: TimeInterval) {
    guard let player else {
      pendingSeekTime = time
      AppLogger.player.debug("Player not ready, storing pending seek to \(time)s")
      return
    }

    mediaProgress.currentTime = time

    let seekTime = CMTime(seconds: time, preferredTimescale: 1000)
    player.seek(to: seekTime) { _ in
      AppLogger.player.debug("Seeked to position: \(time)s")
      if player.timeControlStatus == .playing, let model = self.playbackProgress as? PlaybackProgressViewModel {
        model.updateProgress()
      }
    }
    PlaybackHistory.record(itemID: id, action: .seek, position: time)
  }

  func stopPlayer() {
    player?.pause()

    PlaybackHistory.record(itemID: id, action: .pause, position: mediaProgress.currentTime)

    if let timeObserver {
      player?.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }

    player = nil

    try? audioSession.setActive(false)

    volumeObservation?.invalidate()
    volumeObservation = nil

    itemObservation?.cancel()
    cancellables.removeAll()

    nowPlaying.clear()
  }
}

extension BookPlayerModel {
  private func setupSession(forceTranscode: Bool) async throws {
    item = try await sessionManager.ensureSession(
      itemID: id,
      item: item,
      mediaProgress: mediaProgress,
      forceTranscode: forceTranscode
    )

    if let pendingSeekTime {
      mediaProgress.currentTime = pendingSeekTime
      self.pendingSeekTime = nil
      AppLogger.player.info("Using pending seek time: \(pendingSeekTime)s")
    } else {
      applySmartRewind(reason: .afterPause)
    }
  }

  private func syncSessionProgress() {
    guard sessionManager.current != nil else { return }

    Task {
      do {
        try await sessionManager.syncProgress(currentTime: mediaProgress.currentTime)
      } catch {
        AppLogger.player.error("Failed to sync session progress: \(error)")

        if sessionManager.current?.isRemote == true && isSessionNotFoundError(error) {
          AppLogger.player.debug("Remote session not found (404) - triggering recovery")
          handleStreamFailure(error: error)
        }
      }
    }

    syncPlayback()
  }

  private func isSessionNotFoundError(_ error: Error) -> Bool {
    let errorString = error.localizedDescription.lowercased()
    let nsError = error as NSError

    return errorString.contains("404") || errorString.contains("file not found")
      || errorString.contains("-1011") || nsError.code == -1011 || nsError.code == 404
  }

  func closeSession() {
    Task {
      let isDownloaded = downloadManager.downloadStates[id] == .downloaded
      try? await sessionManager.closeSession(isDownloaded: isDownloaded)
    }
  }
}

extension BookPlayerModel {
  private enum SmartRewindReason {
    case afterPause
    case onInterruption

    var interval: TimeInterval {
      switch self {
      case .afterPause:
        return UserPreferences.shared.smartRewindInterval
      case .onInterruption:
        return UserPreferences.shared.smartRewindOnInterruptionInterval
      }
    }

    var minimumTimeSinceLastPlayed: TimeInterval? {
      switch self {
      case .afterPause:
        return 10 * 60
      case .onInterruption:
        return nil
      }
    }
  }

  private func applySmartRewind(reason: SmartRewindReason) {
    let interval = reason.interval
    let minimumTimeSinceLastPlayed = reason.minimumTimeSinceLastPlayed

    guard interval > 0 else {
      AppLogger.player.debug("Smart rewind is disabled")
      return
    }

    if let minimumTime = minimumTimeSinceLastPlayed {
      let timeSinceLastPlayed = Date().timeIntervalSince(mediaProgress.lastPlayedAt)
      guard timeSinceLastPlayed >= minimumTime else {
        AppLogger.player.debug(
          "Smart rewind not applied - only \(Int(timeSinceLastPlayed / 60)) minutes since last playback"
        )
        return
      }
    }

    let currentTime = mediaProgress.currentTime
    var rewindTarget = currentTime - interval

    if let chapters = item?.orderedChapters, !chapters.isEmpty {
      if let currentChapter = chapters.first(where: { chapter in
        currentTime >= chapter.start && currentTime < chapter.end
      }) {
        rewindTarget = max(currentChapter.start, rewindTarget)
        AppLogger.player.debug(
          "Smart rewind bounded by chapter '\(currentChapter.title)' starting at \(currentChapter.start)s"
        )
      }
    }

    let newTime = max(0, rewindTarget)
    mediaProgress.currentTime = newTime

    if let player {
      let seekTime = CMTime(seconds: newTime, preferredTimescale: 1000)
      player.seek(to: seekTime)
    }

    AppLogger.player.info(
      "Smart rewind applied: rewound \(Int(currentTime - newTime))s"
    )
  }
}

extension BookPlayerModel {
  private func onLoad() {
    isLoading = true

    Task {
      observeMediaProgress()

      await loadLocalBookIfAvailable()

      do {
        try await setupSession(forceTranscode: false)

        autoDownloadIfNeeded()
      } catch {
        AppLogger.player.error("Background session fetch failed: \(error)")
      }

      if player == nil {
        do {
          try await setupAudioPlayer()
        } catch {
          AppLogger.player.error("Failed to setup player: \(error)")
          Toast(error: "Failed to setup audio player").show()
          playerManager.clearCurrent()
        }
      }

      isLoading = false
    }
  }

  private func autoDownloadIfNeeded() {
    let mode = userPreferences.autoDownloadBooks

    guard let item, !item.isDownloaded, mode != .off else { return }

    let networkMonitor = NetworkMonitor.shared

    let shouldAutoDownload: Bool
    switch mode {
    case .off:
      return
    case .wifiOnly:
      shouldAutoDownload = networkMonitor.interfaceType == .wifi
    case .wifiAndCellular:
      shouldAutoDownload = networkMonitor.isConnected
    }

    guard shouldAutoDownload else {
      AppLogger.player.debug("Auto-download skipped (mode: \(mode.rawValue))")
      return
    }

    let delay = userPreferences.autoDownloadDelay
    if delay == .none {
      AppLogger.player.info("Auto-download starting (mode: \(mode.rawValue))")
      try? item.download()
    } else {
      AppLogger.player.info("Auto-download will start after \(delay.displayName) of listening")
    }
  }

  private func checkAutoDownloadAfterListening() {
    let mode = userPreferences.autoDownloadBooks
    let delay = userPreferences.autoDownloadDelay

    guard let item,
      !item.isDownloaded,
      mode != .off,
      delay != .none,
      downloadManager.downloadStates[id] == .notDownloaded,
      !downloadManager.isDownloading(for: id),
      let session = sessionManager.current
    else { return }

    let listeningSeconds = Int(session.timeListening + session.pendingListeningTime)
    guard listeningSeconds >= delay.rawValue else { return }

    let networkMonitor = NetworkMonitor.shared
    let shouldDownload: Bool
    switch mode {
    case .off:
      return
    case .wifiOnly:
      shouldDownload = networkMonitor.interfaceType == .wifi
    case .wifiAndCellular:
      shouldDownload = networkMonitor.isConnected
    }

    guard shouldDownload else { return }

    AppLogger.player.info("Auto-download starting after \(listeningSeconds)s of listening")
    try? item.download()
  }

  private func setupAudioPlayer() async throws {
    guard let item else {
      throw Audiobookshelf.AudiobookshelfError.networkError("No item available")
    }

    let playerItem: AVPlayerItem

    let tracks = item.orderedTracks
    if tracks.count > 1 {
      playerItem = try await createCompositionPlayerItem(from: tracks)
      AppLogger.player.debug("Created composition with \(tracks.count) tracks")
    } else {
      guard let track = item.track(at: 0) else {
        AppLogger.player.error("Failed to get track at time 0")
        Toast(error: "Failed to get track").show()
        isLoading = false
        playerManager.clearCurrent()
        throw Audiobookshelf.AudiobookshelfError.networkError("Failed to get track")
      }

      let trackURL = sessionManager.current?.url(for: track) ?? track.localPath
      guard let trackURL else {
        AppLogger.player.error("No URL available for track")
        throw Audiobookshelf.AudiobookshelfError.networkError("Failed to get track URL")
      }

      playerItem = AVPlayerItem(url: trackURL)
    }

    let player = AVPlayer(playerItem: playerItem)
    self.player = player
    player.volume = Float(userPreferences.volumeLevel)

    if mediaProgress.currentTime > 0 {
      let seekTime = CMTime(seconds: mediaProgress.currentTime, preferredTimescale: 1000)
      player.seek(to: seekTime) { _ in
        AppLogger.player.debug(
          "Seeked to position: \(self.mediaProgress.currentTime)s"
        )
      }
    }

    configurePlayerComponents(player: player)

    syncPlayback()

    if pendingPlay {
      onPlayTapped()
    }
  }

  private func configurePlayerComponents(player: AVPlayer) {
    setupPlayerObservers()
    setupTimeObserver()

    speed = SpeedPickerSheetViewModel(player: player)

    if let item {
      bookmarks = BookmarkViewerSheetViewModel(item: .local(item), initialTime: 0)
    }

    if let sessionChapters = item?.orderedChapters, !sessionChapters.isEmpty {
      chapters = ChapterPickerSheetViewModel(
        itemID: id,
        chapters: sessionChapters,
        mediaProgress: mediaProgress,
        player: player
      )
      AppLogger.player.debug(
        "Loaded \(sessionChapters.count) chapters from play session info"
      )
    } else {
      chapters = nil
      AppLogger.player.debug("No chapters available in play session info")
    }

    timer = TimerPickerSheetViewModel(player: player, chapters: chapters, speed: speed)

    if let playbackProgress = playbackProgress as? PlaybackProgressViewModel {
      playbackProgress.configure(
        player: player,
        chapters: chapters,
        speed: speed
      )
    }

    configureAudioSession()

    nowPlaying.configure(
      player: player,
      speed: speed,
      chapters: chapters,
      mediaProgress: mediaProgress
    )
  }

  private func loadLocalBookIfAvailable() async {
    do {
      if let existingItem = try LocalBook.fetch(bookID: id) {
        AppLogger.player.info("Book is downloaded, loading local files instantly")

        self.item = existingItem
        AppLogger.player.debug(
          "Found existing progress: \(self.mediaProgress.currentTime)s"
        )

        if downloadManager.downloadStates[id] == .downloaded {
          try await setupAudioPlayer()
          isLoading = false
        }
      }
    } catch {
      downloadManager.deleteDownload(for: id)
      AppLogger.player.error("Failed to load local book item: \(error)")
      Toast(error: "Can't access download. Streaming instead.").show()
    }
  }

  private func createCompositionPlayerItem(
    from tracks: [Track]
  )
    async throws -> AVPlayerItem
  {
    let composition = AVMutableComposition()

    guard
      let audioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else {
      throw Audiobookshelf.AudiobookshelfError.compositionError("Failed to create audio track")
    }

    var currentTime = CMTime.zero

    for track in tracks.sorted(by: { $0.index < $1.index }) {
      let trackURL = sessionManager.current?.url(for: track) ?? track.localPath
      guard let trackURL else {
        AppLogger.player.warning("Skipping track \(track.index) - no URL")
        continue
      }

      let asset = AVURLAsset(url: trackURL)
      let assetTracks = try await asset.loadTracks(withMediaType: .audio)

      guard let assetAudioTrack = assetTracks.first else {
        AppLogger.player.warning("Skipping track \(track.index) - no audio track")
        continue
      }

      let trackDuration = CMTime(seconds: track.duration, preferredTimescale: 600)
      let timeRange = CMTimeRange(start: .zero, duration: trackDuration)

      do {
        try audioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: currentTime)
        currentTime = CMTimeAdd(currentTime, trackDuration)
        AppLogger.player.debug(
          "Added track \(track.index) at time \(CMTimeGetSeconds(currentTime))"
        )
      } catch {
        AppLogger.player.error(
          "Failed to insert track \(track.index): \(error)"
        )
      }
    }

    return AVPlayerItem(asset: composition)
  }

  private func isPlayerUsingRemoteURL() -> Bool {
    guard let player = self.player,
      let currentItem = player.currentItem,
      let asset = currentItem.asset as? AVURLAsset
    else {
      return false
    }

    return !asset.url.absoluteString.hasPrefix("file")
  }

  private func reloadPlayer() async {
    guard let player, let item else {
      AppLogger.player.warning("Cannot reload player - missing player or item")
      return
    }

    let playerTime = player.currentTime()
    let currentTimeSeconds: TimeInterval
    if playerTime.isValid && !playerTime.isIndefinite {
      currentTimeSeconds = max(CMTimeGetSeconds(playerTime), mediaProgress.currentTime)
    } else {
      currentTimeSeconds = mediaProgress.currentTime
    }

    AppLogger.player.info("Reloading player at position: \(currentTimeSeconds)s")

    let currentTime = CMTime(seconds: currentTimeSeconds, preferredTimescale: 1000)
    let wasPlaying = isPlaying

    do {
      let playerItem: AVPlayerItem

      let tracks = item.orderedTracks
      if tracks.count > 1 {
        playerItem = try await createCompositionPlayerItem(from: tracks)
        AppLogger.player.debug("Recreated composition for \(tracks.count) tracks")
      } else {
        guard let track = item.track(at: 0) else {
          AppLogger.player.error("Failed to get track at time 0")
          Toast(error: "Failed to get track").show()
          return
        }

        let trackURL = sessionManager.current?.url(for: track) ?? track.localPath
        guard let trackURL else {
          AppLogger.player.error("No URL available for track")
          Toast(error: "Failed to get track URL").show()
          return
        }

        playerItem = AVPlayerItem(url: trackURL)
        AppLogger.player.debug("Using URL: \(trackURL)")
      }

      player.replaceCurrentItem(with: playerItem)
      player.volume = Float(userPreferences.volumeLevel)
      setupPlayerObservers()
      setupTimeObserver()

      player.seek(to: currentTime) { [weak self] _ in
        AppLogger.player.info("Restored playback position and state after reload")
        guard let self else { return }
        if wasPlaying || self.pendingPlay {
          self.onPlayTapped()
        }
      }

    } catch {
      AppLogger.player.error("Failed to reload player: \(error)")
      Toast(error: "Failed to reload playback").show()
    }
  }

}

extension BookPlayerModel {
  private func observeSpeedChanged() {
    withObservationTracking {
      _ = speed.playbackSpeed
    } onChange: { [weak self] in
      guard let self else { return }

      RunLoop.main.perform {
        if let playbackProgress = self.playbackProgress as? PlaybackProgressViewModel {
          playbackProgress.updateProgress()
          self.syncPlayback()
        }

        self.watchConnectivity.sendPlaybackRate(self.speed.playbackSpeed)

        self.observeSpeedChanged()
      }
    }

    watchConnectivity.sendPlaybackRate(speed.playbackSpeed)
  }

  private func observeVolumeLevelChanged() {
    userPreferences.objectWillChange
      .sink { [weak self] _ in
        guard let self, let player = self.player else { return }
        player.volume = Float(userPreferences.volumeLevel)
      }
      .store(in: &cancellables)
  }

  private func setupHistory() {
    history = PlaybackHistorySheetViewModel(
      itemID: id,
      title: title
    ) { [weak self] time in
      self?.seekToTime(time)
    }
  }

  private func observeMediaProgress() {
    withObservationTracking {
      _ = mediaProgress.currentTime
    } onChange: { [weak self] in
      guard let self else { return }

      RunLoop.main.perform {
        if !self.isPlaying {
          let currentTime = CMTime(seconds: self.mediaProgress.currentTime, preferredTimescale: 1000)
          self.onTimeChanged(currentTime)
          self.player?.seek(to: currentTime)
        }
        self.observeMediaProgress()
      }
    }
  }

  private func setupPlayerObservers() {
    guard let player else { return }

    player.publisher(for: \.timeControlStatus)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] status in
        guard let self else { return }

        let isNowPlaying = status == .playing
        self.handlePlaybackStateChange(isNowPlaying)

        if status == .waitingToPlayAtSpecifiedRate {
          self.isLoading = true
        } else if status == .playing || status == .paused {
          self.isLoading = false
        }

        if isNowPlaying && self.timeObserver == nil {
          AppLogger.player.info("Time observer was nil, re-setting up")
          self.setupTimeObserver()
        }
      }
      .store(in: &cancellables)

    if let currentItem = player.currentItem {
      currentItem.publisher(for: \.status)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] status in
          guard let self else { return }
          switch status {
          case .readyToPlay:
            self.isLoading = false
            self.recoveryAttempts = 0
            if self.pendingPlay {
              self.onPlayTapped()
            }

          case .failed:
            self.isLoading = false
            let errorMessage = currentItem.error?.localizedDescription ?? "Unknown error"
            AppLogger.player.error("Player item failed: \(errorMessage)")
            self.handleStreamFailure(error: currentItem.error)
          case .unknown:
            self.isLoading = true
          @unknown default:
            break
          }
        }
        .store(in: &cancellables)

      NotificationCenter.default.publisher(for: AVPlayerItem.playbackStalledNotification)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
          AppLogger.player.warning("Playback stalled - attempting recovery")
          self?.handleStreamFailure(error: nil)
        }
        .store(in: &cancellables)

      NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] notification in
          let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
          AppLogger.player.error(
            "Failed to play to end: \(error?.localizedDescription ?? "Unknown")"
          )
          self?.handleStreamFailure(error: error)
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

    volumeObservation = audioSession.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
      guard let self, let old = change.oldValue, let new = change.newValue else { return }
      self.handleVolumeChange(from: old, to: new)
    }

    NotificationCenter.default.publisher(
      for: AVPlayerItem.newErrorLogEntryNotification,
      object: player.currentItem
    )
    .receive(on: DispatchQueue.main)
    .sink { notification in
      guard let item = notification.object as? AVPlayerItem,
        let event = item.errorLog()?.events.last
      else {
        return
      }
      AppLogger.player.error(
        "Player error \(event.errorDomain), \(event.errorStatusCode), \(event.errorComment ?? "Unknown error")"
      )
    }
    .store(in: &cancellables)
  }

  private func setupTimeObserver() {
    guard let player else { return }

    let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: nil) {
      [weak self] time in
      self?.onTimeChanged(time)
    }
  }

  private func onTimeChanged(_ time: CMTime) {
    if time.isValid && !time.isIndefinite {
      let currentTime = CMTimeGetSeconds(time)
      if currentTime > 0 || self.mediaProgress.currentTime == 0 {
        self.mediaProgress.currentTime = currentTime
      }

      self.timerSecondsCounter += 1

      if self.timerSecondsCounter % 20 == 0 {
        self.updateMediaProgress()
        self.checkAutoDownloadAfterListening()
      }
    }
  }
}

extension BookPlayerModel {
  private func setupDownloadStateBinding(bookID: String) {
    downloadManager.$downloadStates
      .receive(on: DispatchQueue.main)
      .map { states in
        states[bookID] ?? .notDownloaded
      }
      .sink { [weak self] downloadState in
        self?.downloadState = downloadState
      }
      .store(in: &cancellables)

    itemObservation = Task { [weak self] in
      for await updatedItem in LocalBook.observe(where: \.bookID, equals: bookID) {
        guard !Task.isCancelled, let self else { continue }

        self.item = updatedItem

        if updatedItem.isDownloaded, self.isPlayerUsingRemoteURL() {
          AppLogger.player.info("Download completed, refreshing player to use local files")
          await self.reloadPlayer()
        }
      }
    }
  }
}

extension BookPlayerModel {
  private func configureAudioSession() {
    do {
      try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
      try audioSession.setActive(true)
    } catch {
      AppLogger.player.error("Failed to configure audio session: \(error)")
    }
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
      AppLogger.player.info("Audio interruption began")
      interruptionBeganAt = isPlaying ? Date() : nil

    case .ended:
      applySmartRewind(reason: .onInterruption)

      if interruptionBeganAt != nil,
        let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
        AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
      {
        AppLogger.player.info("Audio interruption ended - resuming playback")
        try? audioSession.setActive(true)
        player?.play()
      } else if let beganAt = interruptionBeganAt, Date().timeIntervalSince(beganAt) < 60 * 5 {
        AppLogger.player.info("Audio interruption ended - resuming playback (within 5 minutes)")
        try? audioSession.setActive(true)
        player?.play()
      } else {
        AppLogger.player.info("Audio interruption ended - not resuming")
      }

    @unknown default:
      break
    }
  }

  private func handleMediaServicesReset() {
    AppLogger.player.warning(
      "Media services were reset - reconfiguring audio session and remote commands"
    )

    let wasPlaying = isPlaying
    configureAudioSession()

    if wasPlaying {
      onPlayTapped()
    }
  }

  private func handleVolumeChange(from old: Float, to new: Float) {
    if new == 0 && old > 0 {
      AppLogger.player.info("Volume dropped to 0 - pausing playback")
      interruptionBeganAt = isPlaying ? Date() : nil
      player?.pause()
    } else if new > 0 && old == 0, let beganAt = interruptionBeganAt {
      if Date().timeIntervalSince(beganAt) < 60 * 5 {
        AppLogger.player.info("Volume restored from 0 - resuming playback")
        applySmartRewind(reason: .onInterruption)
        player?.play()
      }
      interruptionBeganAt = nil
    }
  }
}

extension BookPlayerModel {
  private func updateMediaProgress() {
    Task { @MainActor in
      do {
        if isPlaying, let lastTime = lastPlaybackAt {
          let timeListened = Date().timeIntervalSince(lastTime)
          sessionManager.current?.pendingListeningTime += timeListened
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
        AppLogger.player.error("Failed to update playback progress: \(error)")
        Toast(error: "Failed to update playback progress").show()
      }

      nowPlaying.update()
    }
  }

  private func handlePlaybackStateChange(_ isNowPlaying: Bool) {
    AppLogger.player.debug(
      "🎵 handlePlaybackStateChange: isNowPlaying=\(isNowPlaying), current isPlaying=\(isPlaying)"
    )

    let now = Date()

    if isNowPlaying && !isPlaying {
      AppLogger.player.debug("🎵 State: Starting playback")
      PlaybackHistory.record(itemID: id, action: .play, position: mediaProgress.currentTime)
      lastPlaybackAt = now
      mediaProgress.lastPlayedAt = Date()
      sessionManager.notifyPlaybackStarted()
    } else if !isNowPlaying && isPlaying {
      AppLogger.player.debug("🎵 State: Stopping playback")
      PlaybackHistory.record(itemID: id, action: .pause, position: mediaProgress.currentTime)
      if let lastPlaybackAt {
        let timeListened = now.timeIntervalSince(lastPlaybackAt)
        sessionManager.current?.pendingListeningTime += timeListened
        mediaProgress.lastPlayedAt = Date()
        syncSessionProgress()
      }
      lastPlaybackAt = nil

      recordBookCompletionIfNeeded()
      sessionManager.notifyPlaybackStopped()
    } else {
      AppLogger.player.debug(
        "🎵 State: No change (isNowPlaying=\(isNowPlaying), isPlaying=\(isPlaying))"
      )
    }

    try? mediaProgress.save()

    isPlaying = isNowPlaying
    syncPlayback()
  }

  private func recordBookCompletionIfNeeded() {
    guard
      !mediaProgress.isFinished,
      player?.status == .readyToPlay,
      mediaProgress.duration > 0,
      mediaProgress.remaining <= 60
    else { return }

    Task {
      try? await item?.markAsFinished()
    }

    ReviewRequestManager.shared.recordBookCompletion()
    playerManager.playNext()
  }
}

extension BookPlayerModel {
  private func handleStreamFailure(error: Error?) {
    guard !isRecovering else {
      AppLogger.player.debug("Already recovering, skipping duplicate recovery attempt")
      return
    }

    guard recoveryAttempts < maxRecoveryAttempts else {
      AppLogger.player.warning("Max recovery attempts reached, giving up")
      let errorMessage = error?.localizedDescription ?? "Stream unavailable"
      Toast(error: "Playback failed: \(errorMessage)").show()
      playerManager.clearCurrent()
      return
    }

    let isDownloaded = downloadManager.downloadStates[id] == .downloaded
    guard !isDownloaded else {
      AppLogger.player.debug("Book is downloaded, cannot recover from stream failure")
      return
    }

    isRecovering = true

    AppLogger.player.warning(
      "Stream failure detected (attempt \(self.recoveryAttempts)/\(self.maxRecoveryAttempts))"
    )

    Task {
      await recoverSession()
    }
  }

  private func recoverSession() async {
    guard let player else {
      isRecovering = false
      return
    }

    recoveryAttempts += 1

    let isDownloaded = downloadManager.downloadStates[id] == .downloaded

    player.pause()
    isLoading = true

    if !isDownloaded {
      Toast(message: "Reconnecting...").show()
    }

    let delay = min(pow(2.0, Double(recoveryAttempts - 1)), 8.0)
    if delay > 0 && isRecovering {
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    do {
      try await setupSession(forceTranscode: recoveryAttempts > 1)

      if !isDownloaded {
        await reloadPlayer()
        Toast(message: "Reconnected").show()
      } else {
        AppLogger.player.debug("Session recreated for downloaded book (for progress sync)")
      }

      isLoading = false
      isRecovering = false
    } catch {
      AppLogger.player.error("Failed to recover session: \(error)")

      isLoading = false
      isRecovering = false

      if recoveryAttempts < maxRecoveryAttempts && !isDownloaded {
        handleStreamFailure(error: error)
      } else {
        Toast(error: "Unable to reconnect. Please try again later.").show()
        playerManager.clearCurrent()
      }
    }
  }
}

extension BookPlayerModel {
  private func syncPlayback() {
    guard let item else { return }

    let state = PlaybackState(
      bookID: item.bookID,
      title: item.title,
      author: item.authorNames,
      coverURL: item.coverURL,
      currentTime: mediaProgress.currentTime,
      duration: mediaProgress.duration,
      isPlaying: isPlaying,
      playbackSpeed: speed.playbackSpeed
    )

    if let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS"),
      let data = try? JSONEncoder().encode(state)
    {
      sharedDefaults.set(data, forKey: "playbackState")
      WidgetCenter.shared.reloadAllTimelines()
    }

    WatchConnectivityManager.shared.syncProgress(item.bookID)
  }
}
