import API
import AVFoundation
import Combine
import Logging
import MediaPlayer
import Models
import Nuke
import SwiftData
import SwiftUI

final class BookPlayerModel: BookPlayer.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let playerManager = PlayerManager.shared
  private let sessionManager = SessionManager.shared
  private let userPreferences = UserPreferences.shared

  private let audioSession = AVAudioSession.sharedInstance()
  private var player: AudioPlayer?

  private var cancellables = Set<AnyCancellable>()
  private var item: (any PlayableItem)?
  private var itemObservation: Task<Void, Never>?
  private var mediaProgress: MediaProgress
  private var episodeID: String?
  private var lastSyncedTime: Double = 0
  private var pendingPlay: Bool = false
  private var pendingSeekTime: TimeInterval?

  private var lastPlaybackAt: Date?

  private let downloadManager = DownloadManager.shared

  private var nowPlaying: NowPlayingManager
  private var widgetManager: WidgetManager

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

    widgetManager = WidgetManager(
      id: book.id,
      title: book.title,
      author: book.authorName,
      coverURL: book.coverURL(raw: false)
    )

    super.init(
      id: book.id,
      title: book.title,
      author: book.authorName,
      coverURL: book.coverURL(raw: true),
      speed: FloatPickerSheet.Model(),
      timer: TimerPickerSheet.Model(),
      bookmarks: BookmarkViewerSheet.Model(),
      history: PlaybackHistorySheet.Model(),
      playbackProgress: PlaybackProgressViewModel(itemID: book.id, mediaProgress: mediaProgress, title: book.title)
    )

    setupDownloadStateBinding(bookID: book.id)
    setupHistory()

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

    widgetManager = WidgetManager(
      id: item.bookID,
      title: item.title,
      author: item.authorNames,
      coverURL: item.coverURL(raw: false)
    )

    super.init(
      id: item.bookID,
      title: item.title,
      author: item.authorNames,
      coverURL: item.coverURL(raw: true),
      speed: FloatPickerSheet.Model(),
      timer: TimerPickerSheet.Model(),
      bookmarks: BookmarkViewerSheet.Model(),
      history: PlaybackHistorySheet.Model(),
      playbackProgress: PlaybackProgressViewModel(itemID: item.bookID, mediaProgress: mediaProgress, title: item.title)
    )

    setupDownloadStateBinding(bookID: item.bookID)
    setupHistory()

    onLoad()
  }

  init(_ episode: LocalEpisode) {
    self.item = episode
    self.episodeID = episode.episodeID

    do {
      self.mediaProgress = try MediaProgress.getOrCreate(for: episode.episodeID, duration: episode.duration)
    } catch {
      fatalError("Failed to create MediaProgress for episode \(episode.episodeID): \(error)")
    }

    nowPlaying = NowPlayingManager(
      id: episode.episodeID,
      title: episode.title,
      author: episode.podcast?.author,
      coverURL: episode.coverURL,
      current: mediaProgress.currentTime,
      duration: mediaProgress.duration
    )

    widgetManager = WidgetManager(
      id: episode.episodeID,
      title: episode.title,
      author: episode.podcast?.author,
      coverURL: episode.coverURL
    )

    super.init(
      id: episode.episodeID,
      podcastID: episode.podcast?.podcastID,
      title: episode.title,
      author: episode.podcast?.author,
      coverURL: episode.coverURL,
      speed: FloatPickerSheet.Model(),
      timer: TimerPickerSheet.Model(),
      bookmarks: nil,
      history: PlaybackHistorySheet.Model(),
      playbackProgress: PlaybackProgressViewModel(
        itemID: episode.episodeID,
        mediaProgress: mediaProgress,
        title: episode.title
      )
    )

    setupDownloadStateBinding(episodeID: episode.episodeID)
    setupHistory()

    onLoad()
  }

  init(
    _ episode: PodcastEpisode,
    podcastID: String,
    podcastTitle: String,
    podcastAuthor: String?,
    coverURL: URL?
  ) {
    self.item = nil
    self.episodeID = episode.id

    do {
      self.mediaProgress = try MediaProgress.getOrCreate(
        for: episode.id,
        duration: episode.duration ?? 0
      )
    } catch {
      fatalError("Failed to create MediaProgress for episode \(episode.id): \(error)")
    }

    nowPlaying = NowPlayingManager(
      id: episode.id,
      title: episode.title,
      author: podcastAuthor,
      coverURL: coverURL,
      current: mediaProgress.currentTime,
      duration: mediaProgress.duration
    )

    widgetManager = WidgetManager(
      id: episode.id,
      title: episode.title,
      author: podcastAuthor,
      coverURL: coverURL
    )

    super.init(
      id: episode.id,
      podcastID: podcastID,
      title: episode.title,
      author: podcastAuthor,
      coverURL: coverURL,
      speed: FloatPickerSheet.Model(),
      timer: TimerPickerSheet.Model(),
      bookmarks: nil,
      history: PlaybackHistorySheet.Model(),
      playbackProgress: PlaybackProgressViewModel(
        itemID: episode.id,
        mediaProgress: mediaProgress,
        title: episode.title
      )
    )

    setupDownloadStateBinding(episodeID: episode.id)
    setupHistory()

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
            reloadPlayer()
          } else {
            AppLogger.player.info("Player using local files, no reload needed")
          }
        } catch {
          AppLogger.player.error("Failed to recreate session: \(error)")
        }
      }
    }

    applySmartRewind(reason: .afterPause)

    lastSyncedTime = mediaProgress.currentTime
    player.resume()
    try? audioSession.setActive(true)

    if let timerViewModel = timer as? TimerPickerSheetViewModel {
      timerViewModel.activateAutoTimerIfNeeded()
    }

    pendingPlay = false
  }

  override func onSkipForwardTapped(seconds: Double) {
    guard let player else { return }
    let currentTime = player.time
    let newTime = currentTime + seconds
    seekToTime(newTime)
  }

  override func onSkipBackwardTapped(seconds: Double) {
    guard let player else { return }
    let currentTime = player.time
    let newTime = max(0, currentTime - seconds)
    seekToTime(newTime)
  }

  override func onBookmarksTapped() {
    if let player {
      bookmarks?.currentTime = Int(ceil(player.time))
    }
    bookmarks?.isPresented = true
  }

  func getCurrentTime() -> Int? {
    guard let player else { return nil }
    return Int(ceil(player.time))
  }

  override func onHistoryTapped() {
    history?.isPresented = true
  }

  override func onDownloadTapped() {
    if let localBook = item as? LocalBook {
      switch downloadState {
      case .downloading:
        downloadState = .notDownloaded
        downloadManager.cancelDownload(for: id)
      case .downloaded:
        localBook.removeDownload()
      case .notDownloaded:
        downloadState = .downloading(progress: 0)
        try? localBook.download()
      }
    } else if let episode = item as? LocalEpisode, let podcast = episode.podcast {
      switch downloadState {
      case .downloading:
        downloadState = .notDownloaded
        downloadManager.cancelDownload(for: episode.episodeID)
      case .downloaded:
        downloadManager.deleteEpisodeDownload(episodeID: episode.episodeID, podcastID: podcast.podcastID)
      case .notDownloaded:
        downloadState = .downloading(progress: 0)
        downloadManager.startDownload(
          for: episode.episodeID,
          type: .episode(podcastID: podcast.podcastID, episodeID: episode.episodeID),
          info: .init(
            title: title,
            coverURL: coverURL,
            duration: episode.duration,
            size: episode.track?.size,
            startedAt: Date()
          )
        )
      }
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

    player.seek(to: time)
    AppLogger.player.debug("Seeked to position: \(time)s")
    if player.isPlaying, let model = self.playbackProgress as? PlaybackProgressViewModel {
      model.updateProgress()
    }
    PlaybackHistory.record(itemID: id, action: .seek, position: time)
  }

  func stopPlayer() {
    player?.stop()
    player = nil

    PlaybackHistory.record(itemID: id, action: .pause, position: mediaProgress.currentTime)

    try? audioSession.setActive(false)

    volumeObservation?.invalidate()
    volumeObservation = nil

    itemObservation?.cancel()
    cancellables.removeAll()

    nowPlaying.clear()
    widgetManager.clear()
  }
}

extension BookPlayerModel {
  private func setupSession(forceTranscode: Bool) async throws {
    item = try await sessionManager.ensureSession(
      itemID: podcastID ?? id,
      episodeID: episodeID,
      item: item,
      mediaProgress: mediaProgress,
      forceTranscode: forceTranscode
    )

    if let pendingSeekTime {
      mediaProgress.currentTime = pendingSeekTime
      self.pendingSeekTime = nil
      AppLogger.player.info("Using pending seek time: \(pendingSeekTime)s")
    }
  }

  private func syncSessionProgress() {
    guard sessionManager.current != nil, chapters?.isShuffled != true else { return }

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
  }

  private func isSessionNotFoundError(_ error: Error) -> Bool {
    let errorString = error.localizedDescription.lowercased()
    let nsError = error as NSError

    return errorString.contains("404") || errorString.contains("file not found")
      || errorString.contains("-1011") || nsError.code == -1011 || nsError.code == 404
  }

  func closeSession() {
    Task {
      let isDownloaded = item?.isDownloaded ?? false
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

    if let chapters = chapters?.chapters, !chapters.isEmpty {
      let index = chapters.index(for: currentTime)
      let chapter = chapters[index]
      rewindTarget = max(chapter.start, rewindTarget)
      AppLogger.player.debug(
        "Smart rewind bounded by chapter '\(chapter.title)' starting at \(chapter.start)s"
      )
    }

    let newTime = max(0, rewindTarget)
    mediaProgress.currentTime = newTime

    player?.seek(to: newTime)

    AppLogger.player.info(
      "Smart rewind applied: rewound \(Int(currentTime - newTime))s"
    )
  }
}

extension BookPlayerModel {
  private func onLoad() {
    isLoading = true
    loadBackgroundColor()

    Task {
      observeMediaProgress()

      await loadLocalBookIfAvailable()
      await loadLocalEpisodeIfAvailable()

      do {
        try await setupSession(forceTranscode: false)

        autoDownloadIfNeeded()
      } catch {
        AppLogger.player.error("Background session fetch failed: \(error)")
      }

      if player == nil {
        do {
          try setupAudioPlayer()
        } catch {
          AppLogger.player.error("Failed to setup player: \(error)")
          Toast(error: "Failed to setup audio player").show()
          playerManager.clearCurrent()
        }
      }

      isLoading = false
    }
  }

  private func loadBackgroundColor() {
    guard let coverURL else { return }
    Task {
      let request = ImageRequest(url: coverURL)
      guard let image = try? await ImagePipeline.shared.image(for: request),
        let uiColor = image.averageColor
      else { return }
      withAnimation(.easeIn(duration: 0.5)) {
        self.backgroundColor = Color(uiColor)
      }
    }
  }

  private func autoDownloadIfNeeded() {
    guard episodeID == nil else { return }

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
    if delay == .none, let localBook = item as? LocalBook {
      AppLogger.player.info("Auto-download starting (mode: \(mode.rawValue))")
      try? localBook.download()
    } else {
      AppLogger.player.info("Auto-download will start after \(delay.displayName) of listening")
    }
  }

  private func checkAutoDownloadAfterListening() {
    guard episodeID == nil else { return }

    let mode = userPreferences.autoDownloadBooks
    let delay = userPreferences.autoDownloadDelay

    guard let item,
      !item.isDownloaded,
      mode != .off,
      delay != .none,
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
    if let localBook = item as? LocalBook {
      try? localBook.download()
    }
  }

  private func setupAudioPlayer() throws {
    guard let item else {
      throw Audiobookshelf.AudiobookshelfError.networkError("No item available")
    }

    let player = AudioPlayer(mediaProgress: mediaProgress)
    self.player = player

    let session = sessionManager.current
    let tracks = item.orderedTracks

    player.prepare(
      tracks: tracks,
      urlResolver: { track in
        session?.url(for: track) ?? track.localPath
      }
    )

    guard player.hasContent else {
      self.player = nil
      throw Audiobookshelf.AudiobookshelfError.networkError("No playable audio files available")
    }

    player.volume = Float(userPreferences.volumeLevel)

    configurePlayerComponents(player: player)

    isLoading = false
    if pendingPlay {
      onPlayTapped()
    }
  }

  private func configurePlayerComponents(player: AudioPlayer) {
    setupPlayerCallbacks()

    speed = SpeedPickerSheetViewModel(player: player, mediaProgress: mediaProgress)
    volume = VolumeLevelSheetViewModel(player: player)

    if let localBook = item as? LocalBook {
      bookmarks = BookmarkViewerSheetViewModel(item: .local(localBook), initialTime: 0)
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

    timer = TimerPickerSheetViewModel(itemID: id, player: player, chapters: chapters, speed: speed)

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
      chapters: chapters,
      mediaProgress: mediaProgress
    )

    widgetManager.configure(
      player: player,
      chapters: chapters,
      mediaProgress: mediaProgress,
      playbackProgress: playbackProgress
    )

    observeSpeedChanged()
  }

  private func loadLocalBookIfAvailable() async {
    guard episodeID == nil else { return }

    do {
      if let existingItem = try LocalBook.fetch(bookID: id) {
        AppLogger.player.info("Book is downloaded, loading local files instantly")

        self.item = existingItem
        AppLogger.player.debug(
          "Found existing progress: \(self.mediaProgress.currentTime)s"
        )

        if existingItem.isDownloaded {
          try setupAudioPlayer()
          isLoading = false
        }
      }
    } catch {
      downloadManager.deleteDownload(for: id)
      AppLogger.player.error("Failed to load local book item: \(error)")
      Toast(error: "Can't access download. Streaming instead.").show()
    }
  }

  private func loadLocalEpisodeIfAvailable() async {
    guard let episodeID else { return }

    do {
      if let existingEpisode = try LocalEpisode.fetch(episodeID: episodeID),
        existingEpisode.isDownloaded
      {
        AppLogger.player.info("Episode is downloaded, loading local file instantly")
        self.item = existingEpisode

        if existingEpisode.isDownloaded {
          try setupAudioPlayer()
          isLoading = false
        }
      }
    } catch {
      AppLogger.player.error("Failed to load local episode: \(error)")
    }
  }

  private func isPlayerUsingRemoteURL() -> Bool {
    guard player != nil else { return false }
    return item?.isDownloaded != true
  }

  private func reloadPlayer() {
    guard let player else {
      AppLogger.player.warning("Cannot reload player - missing player or item")
      return
    }

    let currentTimeSeconds = max(player.time, mediaProgress.currentTime)
    AppLogger.player.info("Reloading player at position: \(currentTimeSeconds)s")

    let wasPlaying = isPlaying
    let session = sessionManager.current

    player.rebuildQueue(
      urlResolver: { track in
        session?.url(for: track) ?? track.localPath
      }
    )

    player.volume = Float(userPreferences.volumeLevel)

    if wasPlaying || pendingPlay {
      player.resume()
      pendingPlay = false
    }

    AppLogger.player.info("Restored playback position and state after reload")
  }
}

extension BookPlayerModel {
  private func observeSpeedChanged() {
    withObservationTracking {
      _ = speed.value
    } onChange: { [weak self] in
      guard let self else { return }

      RunLoop.main.perform {
        (self.playbackProgress as? PlaybackProgressViewModel)?.updateProgress()
        self.observeSpeedChanged()
      }
    }
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
          self.player?.seek(to: self.mediaProgress.currentTime)
        }
        self.observeMediaProgress()
      }
    }
  }

  private func setupPlayerCallbacks() {
    guard let player else { return }

    player.events
      .sink { [weak self] event in
        guard let self else { return }
        switch event {
        case .timeUpdate(let globalTime):
          self.onTimeChanged(globalTime)

        case .stateChanged(let newState):
          switch newState {
          case .playing:
            self.handlePlaybackStateChange(true)
            self.isLoading = false
            (self.timer as? TimerPickerSheetViewModel)?.resumeLiveActivityIfNeeded()
          case .paused, .stopped:
            self.handlePlaybackStateChange(false)
            self.isLoading = false
            (self.timer as? TimerPickerSheetViewModel)?.pauseLiveActivity()
          case .buffering:
            self.isLoading = true
          case .ready:
            self.isLoading = false
            if self.pendingPlay {
              self.onPlayTapped()
            }
          case .error:
            self.isLoading = false
          }
          self.nowPlaying.update()
          self.widgetManager.update()

        case .stalled:
          AppLogger.player.warning("Playback stalled, pausing")
          player.pause()

        case .error(let error):
          AppLogger.player.error("Player error: \(error?.localizedDescription ?? "Unknown")")
          self.handleStreamFailure(error: error)

        case .finished:
          self.recordBookCompletionIfNeeded()

        case .seek, .rateChanged:
          break
        }
      }
      .store(in: &cancellables)

    setupInterruptionObservers()
  }

  private func setupInterruptionObservers() {
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
  }

  private func onTimeChanged(_ globalTime: TimeInterval) {
    if globalTime > 0 || self.mediaProgress.currentTime == 0 {
      self.mediaProgress.currentTime = globalTime
    }

    if abs(globalTime - lastSyncedTime) >= 10 {
      lastSyncedTime = globalTime
      self.updateMediaProgress()
      self.checkAutoDownloadAfterListening()
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

        self.item = updatedItem as any PlayableItem

        if updatedItem.isDownloaded, self.isPlayerUsingRemoteURL() {
          AppLogger.player.info("Download completed, refreshing player to use local files")
          self.reloadPlayer()
        }
      }
    }
  }

  private func setupDownloadStateBinding(episodeID: String) {
    downloadManager.$downloadStates
      .receive(on: DispatchQueue.main)
      .map { states in
        states[episodeID] ?? .notDownloaded
      }
      .sink { [weak self] downloadState in
        self?.downloadState = downloadState
      }
      .store(in: &cancellables)

    itemObservation = Task { [weak self] in
      for await updatedEpisode in LocalEpisode.observe(where: \.episodeID, equals: episodeID) {
        guard !Task.isCancelled, let self else { continue }

        self.item = updatedEpisode as any PlayableItem

        if updatedEpisode.isDownloaded, self.isPlayerUsingRemoteURL() {
          AppLogger.player.info("Episode download completed, refreshing player to use local file")
          self.reloadPlayer()
        }
      }
    }
  }
}

extension BookPlayerModel {
  private func configureAudioSession() {
    do {
      try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
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
        player?.resume()
      } else if let beganAt = interruptionBeganAt, Date().timeIntervalSince(beganAt) < 60 * 5 {
        AppLogger.player.info("Audio interruption ended - resuming playback (within 5 minutes)")
        try? audioSession.setActive(true)
        player?.resume()
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
        player?.resume()
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
        mediaProgress.playbackSpeed = speed.value
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
      if let player {
        mediaProgress.currentTime = max(player.time, mediaProgress.currentTime)
      }
      PlaybackHistory.record(itemID: id, action: .pause, position: mediaProgress.currentTime)
      if let lastPlaybackAt {
        let timeListened = now.timeIntervalSince(lastPlaybackAt)
        sessionManager.current?.pendingListeningTime += timeListened
        mediaProgress.lastPlayedAt = Date()
        syncSessionProgress()
      }
      lastPlaybackAt = nil

      if mediaProgress.duration > 0 {
        mediaProgress.progress = mediaProgress.currentTime / mediaProgress.duration
      }

      recordBookCompletionIfNeeded()
      sessionManager.notifyPlaybackStopped()
    } else {
      AppLogger.player.debug(
        "🎵 State: No change (isNowPlaying=\(isNowPlaying), isPlaying=\(isPlaying))"
      )
    }

    try? mediaProgress.save()

    isPlaying = isNowPlaying
  }

  private func recordBookCompletionIfNeeded() {
    guard
      chapters?.isShuffled != true,
      !mediaProgress.isFinished,
      mediaProgress.duration > 0,
      mediaProgress.remaining <= 60
    else { return }

    if let localBook = item as? LocalBook {
      Task {
        try? await localBook.markAsFinished()
      }
    } else if let episodeID, let podcastID {
      Task {
        try? MediaProgress.markAsFinished(for: episodeID)
        let episodeProgressID = "\(podcastID)/\(episodeID)"
        try? await audiobookshelf.libraries.markAsFinished(bookID: episodeProgressID)
      }
    }

    ReviewRequestManager.shared.recordBookCompletion()
    playerManager.playNext()
  }
}

extension BookPlayerModel {
  private func handleStreamFailure(error: Error?) {
    if isConnectivityError(error) {
      AppLogger.player.warning("Connectivity error, pausing playback")
      player?.pause()
      Toast(error: "No connection. Try again when you're back online.").show()
      return
    }

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

    guard item?.isDownloaded != true else {
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

  private func isConnectivityError(_ error: Error?) -> Bool {
    guard let urlError = error as? URLError else {
      guard let nsError = error as NSError? else { return false }
      return nsError.domain == NSURLErrorDomain
        && [
          NSURLErrorNotConnectedToInternet,
          NSURLErrorNetworkConnectionLost,
          NSURLErrorTimedOut,
          NSURLErrorCannotFindHost,
          NSURLErrorCannotConnectToHost,
          NSURLErrorDNSLookupFailed,
        ].contains(nsError.code)
    }
    return [
      .notConnectedToInternet,
      .networkConnectionLost,
      .timedOut,
      .cannotFindHost,
      .cannotConnectToHost,
      .dnsLookupFailed,
    ].contains(urlError.code)
  }

  private func recoverSession() async {
    guard player != nil else {
      isRecovering = false
      return
    }

    recoveryAttempts += 1

    let isDownloaded = item?.isDownloaded ?? false

    player?.pause()
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
        reloadPlayer()
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
