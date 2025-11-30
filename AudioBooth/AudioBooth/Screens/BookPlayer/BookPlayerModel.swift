import API
import AVFoundation
import AVKit
import Combine
import MediaPlayer
import Models
import Nuke
import OSLog
import SwiftData
import SwiftUI
import WatchConnectivity
import WidgetKit

final class BookPlayerModel: BookPlayer.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private let sessionManager = SessionManager.shared

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

  private var cover: UIImage?
  private var nowPlayingInfo: [String: Any] = [:]

  private var recoveryAttempts = 0
  private var maxRecoveryAttempts = 3
  private var isRecovering = false

  init(_ book: Book) {
    self.item = nil
    do {
      self.mediaProgress = try MediaProgress.getOrCreate(for: book.id, duration: book.duration)
    } catch {
      fatalError("Failed to create MediaProgress for book \(book.id): \(error)")
    }

    super.init(
      id: book.id,
      title: book.title,
      author: book.authorName,
      coverURL: book.coverURL,
      speed: SpeedPickerSheet.Model(),
      timer: TimerPickerSheet.Model(),
      bookmarks: BookmarkViewerSheet.Model(),
      playbackProgress: PlaybackProgressViewModel()
    )

    setupDownloadStateBinding(bookID: book.id)
    observeSpeedChanged()
    observeSkipIntervalChanges()
    onLoad()
  }

  init(_ item: LocalBook) {
    self.item = item
    do {
      self.mediaProgress = try MediaProgress.getOrCreate(for: item.bookID, duration: item.duration)
    } catch {
      fatalError("Failed to create MediaProgress for item \(item.bookID): \(error)")
    }

    super.init(
      id: item.bookID,
      title: item.title,
      author: item.authorNames,
      coverURL: item.coverURL,
      speed: SpeedPickerSheet.Model(),
      timer: TimerPickerSheet.Model(),
      bookmarks: BookmarkViewerSheet.Model(),
      playbackProgress: PlaybackProgressViewModel()
    )

    setupDownloadStateBinding(bookID: item.bookID)
    observeSpeedChanged()
    observeSkipIntervalChanges()
    onLoad()
  }

  override func onTogglePlaybackTapped() {
    guard let player = player, player.status == .readyToPlay else {
      pendingPlay = true
      return
    }

    if isPlaying {
      player.rate = 0
      try? audioSession.setActive(false)
    } else {
      if sessionManager.current == nil {
        AppLogger.player.warning("Session was closed, recreating in background for progress sync")

        player.rate = speed.playbackSpeed

        Task {
          do {
            try await setupSession()
            AppLogger.player.info("Session recreated successfully (playback continued from cache)")
          } catch {
            AppLogger.player.error("Failed to recreate session: \(error, privacy: .public)")
          }
        }
      } else {
        player.rate = speed.playbackSpeed
      }
      try? audioSession.setActive(true)
    }
  }

  override func onPauseTapped() {
    guard let player = player, player.status == .readyToPlay else {
      return
    }
    player.rate = 0
    try? audioSession.setActive(false)
  }

  override func onPlayTapped() {
    if UserPreferences.shared.shakeToExtendTimer,
      let timer = timer as? TimerPickerSheetViewModel,
      let completedAlert = timer.completedAlert
    {
      completedAlert.onExtendTapped()
      return
    }

    guard let player = player, player.status == .readyToPlay else {
      pendingPlay = true
      return
    }

    if sessionManager.current == nil {
      AppLogger.player.warning("Session was closed, recreating in background for progress sync")

      player.rate = speed.playbackSpeed

      Task {
        do {
          try await setupSession()
          AppLogger.player.info("Session recreated successfully (playback continued from cache)")
        } catch {
          AppLogger.player.error("Failed to recreate session: \(error, privacy: .public)")
        }
      }
    } else {
      player.rate = speed.playbackSpeed
    }

    try? audioSession.setActive(true)
  }

  override func onSkipForwardTapped(seconds: Double) {
    guard let player = player else { return }
    let currentTime = player.currentTime()
    let newTime = CMTimeAdd(currentTime, CMTime(seconds: seconds, preferredTimescale: 1))
    player.seek(to: newTime)
  }

  override func onSkipBackwardTapped(seconds: Double) {
    guard let player = player else { return }
    let currentTime = player.currentTime()
    let newTime = CMTimeSubtract(currentTime, CMTime(seconds: seconds, preferredTimescale: 1))
    let zeroTime = CMTime(seconds: 0, preferredTimescale: 1)
    player.seek(to: CMTimeMaximum(newTime, zeroTime))
  }

  func seekToTime(_ time: TimeInterval) {
    guard let player = player else {
      pendingSeekTime = time
      AppLogger.player.debug("Player not ready, storing pending seek to \(time, privacy: .public)s")
      return
    }

    let seekTime = CMTime(seconds: time, preferredTimescale: 1000)
    player.seek(to: seekTime) { _ in
      AppLogger.player.debug("Seeked to position: \(time, privacy: .public)s")
    }
  }

  override func onBookmarksTapped() {
    if let player = player {
      let time = player.currentTime()
      if time.isValid && !time.isIndefinite {
        bookmarks?.currentTime = Int(ceil(CMTimeGetSeconds(time)))
      }
    }
    bookmarks?.isPresented = true
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
  private func setupSession() async throws {
    let result = try await sessionManager.ensureSession(
      itemID: id,
      item: item,
      mediaProgress: mediaProgress
    )

    if let pendingSeekTime = pendingSeekTime {
      mediaProgress.currentTime = pendingSeekTime
      self.pendingSeekTime = nil
      AppLogger.player.info("Using pending seek time: \(pendingSeekTime, privacy: .public)s")
    } else if result.serverCurrentTime > mediaProgress.currentTime {
      mediaProgress.currentTime = result.serverCurrentTime
      AppLogger.player.info(
        "Using server currentTime for cross-device sync: \(result.serverCurrentTime, privacy: .public)s"
      )
      applySmartRewind()
    } else {
      applySmartRewind()
    }

    if let updatedItem = result.updatedItem {
      item = updatedItem
    }
  }

  private func applySmartRewind() {
    let smartRewindInterval = UserPreferences.shared.smartRewindInterval

    guard smartRewindInterval > 0 else {
      AppLogger.player.debug("Smart rewind is disabled")
      return
    }

    let lastPlayedAt = mediaProgress.lastPlayedAt

    let timeSinceLastPlayed = Date().timeIntervalSince(lastPlayedAt)
    let tenMinutes: TimeInterval = 10 * 60

    guard timeSinceLastPlayed >= tenMinutes else {
      AppLogger.player.debug(
        "Smart rewind not applied - only \(Int(timeSinceLastPlayed / 60), privacy: .public) minutes since last playback"
      )
      return
    }

    let newTime = max(0, mediaProgress.currentTime - smartRewindInterval)
    mediaProgress.currentTime = newTime

    AppLogger.player.info(
      "Smart rewind applied: rewound \(Int(smartRewindInterval), privacy: .public)s after \(Int(timeSinceLastPlayed / 60), privacy: .public) minutes of pause"
    )
  }

  private func setupAudioPlayer() async throws {
    guard let item else {
      throw Audiobookshelf.AudiobookshelfError.networkError("No item available")
    }

    let playerItem: AVPlayerItem

    let tracks = item.orderedTracks
    if tracks.count > 1 {
      playerItem = try await createCompositionPlayerItem(from: tracks)
      AppLogger.player.debug("Created composition with \(tracks.count, privacy: .public) tracks")
    } else {
      guard let track = item.track(at: 0) else {
        AppLogger.player.error("Failed to get track at time 0")
        Toast(error: "Failed to get track").show()
        isLoading = false
        PlayerManager.shared.clearCurrent()
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

    if mediaProgress.currentTime > 0 {
      let seekTime = CMTime(seconds: mediaProgress.currentTime, preferredTimescale: 1000)
      player.seek(to: seekTime) { _ in
        AppLogger.player.debug(
          "Seeked to position: \(self.mediaProgress.currentTime, privacy: .public)s")
      }
    }

    configurePlayerComponents(player: player)

    syncPlayback()

    if pendingPlay {
      player.rate = speed.playbackSpeed
      pendingPlay = false
    }
  }

  private func configurePlayerComponents(player: AVPlayer) {
    configureAudioSession()
    setupPlayerObservers()
    setupTimeObserver()

    speed = SpeedPickerSheetViewModel(player: player)
    let timerViewModel = TimerPickerSheetViewModel()
    timerViewModel.setPlayer(player)
    timer = timerViewModel

    if let localBook = item {
      bookmarks = BookmarkViewerSheetViewModel(item: .local(localBook), initialTime: 0)
    }

    if let sessionChapters = item?.orderedChapters, !sessionChapters.isEmpty {
      chapters = ChapterPickerSheetViewModel(chapters: sessionChapters, player: player)
      timer.maxRemainingChapters = sessionChapters.count - 1
      AppLogger.player.debug(
        "Loaded \(sessionChapters.count, privacy: .public) chapters from play session info")
    } else {
      chapters = nil
      AppLogger.player.debug("No chapters available in play session info")
    }

    if let playbackProgress = playbackProgress as? PlaybackProgressViewModel {
      let totalDuration = item?.orderedTracks.reduce(0.0) { $0 + $1.duration }
      playbackProgress.configure(
        player: player,
        chapters: chapters,
        speed: speed,
        totalDuration: totalDuration
      )
    }

    setupRemoteCommandCenter()
  }

  private func loadLocalBookIfAvailable() async {
    do {
      if let existingItem = try LocalBook.fetch(bookID: id) {
        AppLogger.player.info("Book is downloaded, loading local files instantly")

        self.item = existingItem
        AppLogger.player.debug(
          "Found existing progress: \(self.mediaProgress.currentTime, privacy: .public)s")

        if existingItem.isDownloaded {
          try await setupAudioPlayer()
        }
      }
    } catch {
      downloadManager.deleteDownload(for: id)
      AppLogger.player.error("Failed to load local book item: \(error, privacy: .public)")
      Toast(error: "Can‘t access download. Streaming instead.").show()
    }
  }

  private func observeSpeedChanged() {
    withObservationTracking {
      _ = speed.playbackSpeed
    } onChange: { [weak self] in
      RunLoop.current.perform {
        if let playbackProgress = self?.playbackProgress as? PlaybackProgressViewModel {
          playbackProgress.updateProgress()
          WidgetCenter.shared.reloadAllTimelines()
        }

        self?.observeSpeedChanged()
      }
    }
  }

  private func observeSkipIntervalChanges() {
    let preferences = UserPreferences.shared

    preferences.objectWillChange
      .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        self?.setupRemoteCommandCenter()
      }
      .store(in: &cancellables)
  }

  private func onLoad() {
    Task {
      isLoading = true

      loadCover()

      await loadLocalBookIfAvailable()

      do {
        try await setupSession()

        if UserPreferences.shared.autoDownloadBooks && item?.isDownloaded == false {
          AppLogger.player.info("Auto-download enabled, starting download for book")
          try? item?.download()
        }
      } catch {
        AppLogger.player.error("Background session fetch failed: \(error, privacy: .public)")
      }

      if player == nil {
        do {
          try await setupAudioPlayer()
        } catch {
          AppLogger.player.error("Failed to setup player: \(error, privacy: .public)")
          Toast(error: "Failed to setup audio player").show()
          PlayerManager.shared.clearCurrent()
        }
      }

      isLoading = false
    }
  }

  func loadCover() {
    Task {
      do {
        let request = ImageRequest(url: coverURL)
        cover = try await ImagePipeline.shared.image(for: request)
        setupNowPlayingMetadata()
      } catch {
        AppLogger.player.error(
          "Failed to load cover image for now playing: \(error, privacy: .public)")
      }
    }
  }

  private func setupDownloadStateBinding(bookID: String) {
    downloadManager.$currentProgress
      .receive(on: DispatchQueue.main)
      .map { [weak self] progress in
        if self?.item?.isDownloaded == true || self?.downloadState == .downloaded {
          return .downloaded
        } else if let progress = progress[bookID] {
          return .downloading(progress: progress)
        } else {
          return .notDownloaded
        }
      }
      .sink { [weak self] downloadState in
        self?.downloadState = downloadState
      }
      .store(in: &cancellables)

    itemObservation = Task { [weak self] in
      for await updatedItem in LocalBook.observe(where: \.bookID, equals: bookID) {
        guard !Task.isCancelled, let self else { continue }

        self.item = updatedItem

        self.downloadState = updatedItem.isDownloaded ? .downloaded : .notDownloaded

        if updatedItem.isDownloaded, self.isPlayerUsingRemoteURL() {
          self.refreshPlayerForLocalPlayback()
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
      AppLogger.player.error("Failed to configure audio session: \(error, privacy: .public)")
    }
  }

  private func setupRemoteCommandCenter() {
    let commandCenter = MPRemoteCommandCenter.shared()
    let preferences = UserPreferences.shared

    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.onPlayTapped()
      return .success
    }

    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.onPauseTapped()
      return .success
    }

    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.onTogglePlaybackTapped()
      return .success
    }

    commandCenter.stopCommand.isEnabled = true
    commandCenter.stopCommand.addTarget { [weak self] _ in
      self?.onPauseTapped()
      return .success
    }

    let useChapterNavigation =
      preferences.lockScreenNextPreviousUsesChapters
      && (chapters?.chapters.count ?? 0) >= 2

    if useChapterNavigation {
      commandCenter.skipForwardCommand.isEnabled = false
      commandCenter.skipBackwardCommand.isEnabled = false

      commandCenter.nextTrackCommand.isEnabled = true
      commandCenter.nextTrackCommand.addTarget { [weak self] _ in
        self?.chapters?.onNextChapterTapped()
        return .success
      }

      commandCenter.previousTrackCommand.isEnabled = true
      commandCenter.previousTrackCommand.addTarget { [weak self] _ in
        self?.chapters?.onPreviousChapterTapped()
        return .success
      }
    }

    commandCenter.skipForwardCommand.isEnabled = !useChapterNavigation
    commandCenter.skipForwardCommand.preferredIntervals = [
      NSNumber(value: preferences.skipForwardInterval)
    ]
    commandCenter.skipForwardCommand.addTarget { [weak self] event in
      let interval: Double
      if let skipEvent = event as? MPSkipIntervalCommandEvent, skipEvent.interval > 0 {
        interval = skipEvent.interval
      } else {
        interval = preferences.skipForwardInterval
      }

      self?.onSkipForwardTapped(seconds: interval)
      return .success
    }

    commandCenter.skipBackwardCommand.isEnabled = !useChapterNavigation
    commandCenter.skipBackwardCommand.preferredIntervals = [
      NSNumber(value: preferences.skipBackwardInterval)
    ]
    commandCenter.skipBackwardCommand.addTarget { [weak self] event in
      let interval: Double
      if let skipEvent = event as? MPSkipIntervalCommandEvent, skipEvent.interval > 0 {
        interval = skipEvent.interval
      } else {
        interval = preferences.skipBackwardInterval
      }

      self?.onSkipBackwardTapped(seconds: interval)
      return .success
    }

    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      if useChapterNavigation {
        self?.chapters?.onNextChapterTapped()
      } else {
        self?.onSkipForwardTapped(seconds: preferences.skipForwardInterval)
      }
      return .success
    }

    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      if useChapterNavigation {
        self?.chapters?.onPreviousChapterTapped()
      } else {
        self?.onSkipBackwardTapped(seconds: preferences.skipBackwardInterval)
      }
      return .success
    }

    commandCenter.changePlaybackPositionCommand.isEnabled =
      preferences.lockScreenAllowPlaybackPositionChange
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }

      let offset = self?.chapters?.current?.start ?? 0
      self?.seekToTime(offset + positionEvent.positionTime)
      return .success
    }

    commandCenter.changePlaybackRateCommand.isEnabled = true
    commandCenter.changePlaybackRateCommand.supportedPlaybackRates = speed.speeds.map {
      NSNumber(value: $0)
    }
    commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
      guard let rateEvent = event as? MPChangePlaybackRateCommandEvent else {
        return .commandFailed
      }

      self?.speed.onSpeedChanged(rateEvent.playbackRate)
      return .success
    }

    commandCenter.seekForwardCommand.isEnabled = true
    commandCenter.seekForwardCommand.addTarget { [weak self] _ in
      self?.onSkipForwardTapped(seconds: preferences.skipForwardInterval)
      return .success
    }

    commandCenter.seekBackwardCommand.isEnabled = true
    commandCenter.seekBackwardCommand.addTarget { [weak self] _ in
      self?.onSkipBackwardTapped(seconds: preferences.skipBackwardInterval)
      return .success
    }

    setupNowPlayingMetadata()
  }

  private func setupNowPlayingMetadata() {
    nowPlayingInfo[MPMediaItemPropertyTitle] = title
    nowPlayingInfo[MPMediaItemPropertyArtist] = author

    if let cover {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cover.size) { _ in
        return cover
      }
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  private func updateNowPlayingInfo() {
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] =
      playbackProgress.current + playbackProgress.remaining
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackProgress.current
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? speed.playbackSpeed : 0.0

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  private func setupPlayerObservers() {
    guard let player else { return }

    player.publisher(for: \.rate)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] rate in
        guard let self else { return }

        let isNowPlaying = rate > 0
        self.handlePlaybackStateChange(isNowPlaying)
        self.isPlaying = isNowPlaying

        if isNowPlaying && self.timeObserver == nil {
          AppLogger.player.info("Time observer was nil, re-setting up")
          self.setupTimeObserver()
        }

        self.updateNowPlayingInfo()
      }
      .store(in: &cancellables)

    if let currentItem = player.currentItem {
      currentItem.publisher(for: \.status)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] status in
          switch status {
          case .readyToPlay:
            self?.isLoading = false
            self?.recoveryAttempts = 0
            let duration = currentItem.duration
            if duration.isValid && !duration.isIndefinite {
            }
          case .failed:
            self?.isLoading = false
            let errorMessage = currentItem.error?.localizedDescription ?? "Unknown error"
            AppLogger.player.error("Player item failed: \(errorMessage, privacy: .public)")
            self?.handleStreamFailure(error: currentItem.error)
          case .unknown:
            self?.isLoading = true
          @unknown default:
            break
          }
        }
        .store(in: &cancellables)

      NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled, object: currentItem)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
          AppLogger.player.warning("Playback stalled - attempting recovery")
          self?.handleStreamFailure(error: nil)
        }
        .store(in: &cancellables)

      NotificationCenter.default.publisher(
        for: .AVPlayerItemFailedToPlayToEndTime, object: currentItem
      )
      .receive(on: DispatchQueue.main)
      .sink { [weak self] notification in
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        AppLogger.player.error(
          "Failed to play to end: \(error?.localizedDescription ?? "Unknown", privacy: .public)")
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

    case .ended:
      guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
        return
      }

      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      if options.contains(.shouldResume) {
        AppLogger.player.info("Audio interruption ended - resuming playback")
        player?.rate = speed.playbackSpeed
      } else {
        AppLogger.player.info("Audio interruption ended - not resuming")
      }

    @unknown default:
      break
    }
  }

  private func handleMediaServicesReset() {
    AppLogger.player.warning(
      "Media services were reset - reconfiguring audio session and remote commands")

    let wasPlaying = isPlaying
    configureAudioSession()
    setupRemoteCommandCenter()

    if wasPlaying {
      onPlayTapped()
    }
  }

  private func setupTimeObserver() {
    guard let player = player else { return }

    let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: nil) {
      [weak self] time in
      guard let self else { return }

      if time.isValid && !time.isIndefinite {
        self.mediaProgress.currentTime = CMTimeGetSeconds(time)

        if let model = self.chapters as? ChapterPickerSheetViewModel {
          let previous = model.currentIndex
          model.setCurrentTime(self.mediaProgress.currentTime)

          if let timerViewModel = self.timer as? TimerPickerSheetViewModel {
            timerViewModel.onChapterChanged(
              previous: previous,
              current: model.currentIndex,
              total: model.chapters.count
            )
          }
        }

        if let playbackProgress = self.playbackProgress as? PlaybackProgressViewModel {
          playbackProgress.updateCurrentTime(self.mediaProgress.currentTime)
        }

        self.timerSecondsCounter += 1

        if self.timerSecondsCounter % 20 == 0 {
          self.updateMediaProgress()
        }

        if self.timerSecondsCounter % 2 == 0 {
          self.syncPlayback()
        }

        self.updateNowPlayingInfo()
      }
    }
  }

  private func createCompositionPlayerItem(from tracks: [Track])
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
        AppLogger.player.warning("Skipping track \(track.index, privacy: .public) - no URL")
        continue
      }

      let asset = AVURLAsset(url: trackURL)
      let assetTracks = try await asset.loadTracks(withMediaType: .audio)

      guard let assetAudioTrack = assetTracks.first else {
        AppLogger.player.warning("Skipping track \(track.index, privacy: .public) - no audio track")
        continue
      }

      let trackDuration = CMTime(seconds: track.duration, preferredTimescale: 600)
      let timeRange = CMTimeRange(start: .zero, duration: trackDuration)

      do {
        try audioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: currentTime)
        currentTime = CMTimeAdd(currentTime, trackDuration)
        AppLogger.player.debug(
          "Added track \(track.index, privacy: .public) at time \(CMTimeGetSeconds(currentTime), privacy: .public)"
        )
      } catch {
        AppLogger.player.error(
          "Failed to insert track \(track.index, privacy: .public): \(error, privacy: .public)")
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

  private func refreshPlayerForLocalPlayback() {
    guard let player, let item else {
      AppLogger.player.warning("Cannot refresh player - missing player or item")
      return
    }

    AppLogger.player.info("Refreshing player to use local files")

    let currentTime = player.currentTime()
    let wasPlaying = isPlaying

    player.pause()

    Task {
      do {
        let playerItem: AVPlayerItem

        let tracks = item.orderedTracks
        if tracks.count > 1 {
          playerItem = try await createCompositionPlayerItem(from: tracks)
          AppLogger.player.debug(
            "Recreated composition with local files for \(tracks.count, privacy: .public) tracks")
        } else {
          guard let track = item.track(at: 0) else {
            AppLogger.player.error("Failed to get track at time 0")
            Toast(error: "Failed to get track").show()
            return
          }

          let trackURL = sessionManager.current?.url(for: track) ?? track.localPath
          guard let trackURL else {
            AppLogger.player.error("No URL available for track")
            Toast(error: "Failed to get streaming URL").show()
            return
          }

          playerItem = AVPlayerItem(url: trackURL)
          AppLogger.player.debug("Using URL: \(trackURL, privacy: .public)")
        }

        player.replaceCurrentItem(with: playerItem)
        setupPlayerObservers()
        setupTimeObserver()

        player.seek(to: currentTime) { _ in
          if wasPlaying {
            player.rate = self.speed.playbackSpeed
          }
          AppLogger.player.info(
            "Restored playback position and state after switching to local files")
        }

      } catch {
        AppLogger.player.error(
          "Failed to refresh player for local playback: \(error, privacy: .public)")
        Toast(error: "Failed to switch to downloaded files").show()
      }
    }
  }

  private func handlePlaybackStateChange(_ isNowPlaying: Bool) {
    AppLogger.player.debug(
      "🎵 handlePlaybackStateChange: isNowPlaying=\(isNowPlaying, privacy: .public), current isPlaying=\(self.isPlaying, privacy: .public)"
    )

    let now = Date()

    if isNowPlaying && !isPlaying {
      AppLogger.player.debug("🎵 State: Starting playback")
      lastPlaybackAt = now
      mediaProgress.lastPlayedAt = Date()
      sessionManager.notifyPlaybackStarted()
    } else if !isNowPlaying && isPlaying {
      AppLogger.player.debug("🎵 State: Stopping playback")
      if let last = lastPlaybackAt {
        let timeListened = now.timeIntervalSince(last)
        sessionManager.current?.pendingListeningTime += timeListened
        mediaProgress.lastPlayedAt = Date()
        syncSessionProgress()
      }
      lastPlaybackAt = nil

      markAsFinishedIfNeeded()
      sessionManager.notifyPlaybackStopped()
    } else {
      AppLogger.player.debug(
        "🎵 State: No change (isNowPlaying=\(isNowPlaying, privacy: .public), isPlaying=\(self.isPlaying, privacy: .public))"
      )
    }

    try? mediaProgress.save()
    try? item?.save()

    syncPlayback()
  }

  private func markAsFinishedIfNeeded() {
    guard !mediaProgress.isFinished, player?.status == .readyToPlay else { return }

    let remainingTime = mediaProgress.duration - mediaProgress.currentTime
    let isNearEnd = remainingTime <= 120

    var shouldMarkFinished = isNearEnd

    if let chaptersModel = chapters as? ChapterPickerSheetViewModel {
      let isOnLastChapter =
        chaptersModel.chapters.count > 1
        && chaptersModel.currentIndex == chaptersModel.chapters.count - 1

      shouldMarkFinished = isOnLastChapter
      AppLogger.player.debug(
        "📖 Chapter check: \(isOnLastChapter, privacy: .public), Near end: \(isNearEnd, privacy: .public)"
      )
    } else {
      AppLogger.player.debug(
        "📖 No chapters, using time-based check. Near end: \(isNearEnd, privacy: .public)")
    }

    guard shouldMarkFinished else { return }

    mediaProgress.isFinished = true
    mediaProgress.progress = 1.0
    try? mediaProgress.save()

    ReviewRequestManager.shared.recordBookCompletion()

    Task {
      guard let item else { return }

      do {
        try await item.markAsFinished()
        AppLogger.player.debug("Successfully marked book as finished on server")
      } catch {
        AppLogger.player.error(
          "Failed to update book finished status on server: \(error, privacy: .public)")
      }
    }
  }

  private func syncSessionProgress() {
    guard sessionManager.current != nil else { return }

    Task {
      do {
        try await sessionManager.syncProgress(currentTime: mediaProgress.currentTime)
      } catch {
        AppLogger.player.error("Failed to sync session progress: \(error, privacy: .public)")

        if sessionManager.current?.isRemote == true && isSessionNotFoundError(error) {
          AppLogger.player.debug("Remote session not found (404) - triggering recovery")
          handleStreamFailure(error: error)
        }
      }
    }

    WidgetCenter.shared.reloadAllTimelines()
  }

  private func isSessionNotFoundError(_ error: Error) -> Bool {
    let errorString = error.localizedDescription.lowercased()
    let nsError = error as NSError

    return errorString.contains("404") || errorString.contains("file not found")
      || errorString.contains("-1011") || nsError.code == -1011 || nsError.code == 404
  }

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
        AppLogger.player.error("Failed to update playback progress: \(error, privacy: .public)")
        Toast(error: "Failed to update playback progress").show()
      }
    }
  }

  private func handleStreamFailure(error: Error?) {
    guard !isRecovering else {
      AppLogger.player.debug("Already recovering, skipping duplicate recovery attempt")
      return
    }

    guard recoveryAttempts < maxRecoveryAttempts else {
      AppLogger.player.warning("Max recovery attempts reached, giving up")
      let errorMessage = error?.localizedDescription ?? "Stream unavailable"
      Toast(error: "Playback failed: \(errorMessage)").show()
      PlayerManager.shared.clearCurrent()
      return
    }

    let isDownloaded = item?.isDownloaded ?? false
    guard !isDownloaded else {
      AppLogger.player.debug("Book is downloaded, cannot recover from stream failure")
      return
    }

    isRecovering = true
    recoveryAttempts += 1

    AppLogger.player.warning(
      "Stream failure detected (attempt \(self.recoveryAttempts, privacy: .public)/\(self.maxRecoveryAttempts, privacy: .public))"
    )

    Task {
      await recoverSession()
    }
  }

  private func recoverSession() async {
    guard let player = player else {
      isRecovering = false
      return
    }

    let currentTime = player.currentTime()
    let wasPlaying = isPlaying
    let isDownloaded = item?.isDownloaded ?? false

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
      try await setupSession()

      guard let item else {
        throw Audiobookshelf.AudiobookshelfError.networkError("Failed to recreate session")
      }

      if !isDownloaded {
        let playerItem: AVPlayerItem

        let tracks = item.orderedTracks
        if tracks.count > 1 {
          playerItem = try await createCompositionPlayerItem(from: tracks)
          AppLogger.player.debug(
            "Recreated composition with \(tracks.count, privacy: .public) tracks after recovery")
        } else {
          guard let track = item.track(at: 0) else {
            throw Audiobookshelf.AudiobookshelfError.networkError("Failed to get track")
          }

          let trackURL = sessionManager.current?.url(for: track) ?? track.localPath
          guard let trackURL else {
            throw Audiobookshelf.AudiobookshelfError.networkError("Failed to get track URL")
          }

          playerItem = AVPlayerItem(url: trackURL)
        }

        player.replaceCurrentItem(with: playerItem)
        setupPlayerObservers()
        setupTimeObserver()

        let rewindTime = CMTimeSubtract(currentTime, CMTime(seconds: 5, preferredTimescale: 1000))
        let seekTime = CMTimeMaximum(rewindTime, .zero)

        player.seek(to: seekTime) { [weak self] _ in
          guard let self else { return }

          self.isLoading = false
          self.isRecovering = false

          if wasPlaying {
            player.rate = self.speed.playbackSpeed
          }

          AppLogger.player.debug(
            "Successfully recovered stream at position: \(CMTimeGetSeconds(seekTime), privacy: .public)s (rewound 5s)"
          )
          Toast(message: "Reconnected").show()
        }
      } else {
        isLoading = false
        isRecovering = false

        if wasPlaying {
          player.rate = speed.playbackSpeed
        }

        AppLogger.player.debug("Session recreated for downloaded book (for progress sync)")
      }

    } catch {
      AppLogger.player.error("Failed to recover session: \(error, privacy: .public)")

      isLoading = false
      isRecovering = false

      if recoveryAttempts < maxRecoveryAttempts && !isDownloaded {
        handleStreamFailure(error: error)
      } else {
        Toast(error: "Unable to reconnect. Please try again later.").show()
        PlayerManager.shared.clearCurrent()
      }
    }
  }

  func stopPlayer() {
    player?.rate = 0

    if let timeObserver {
      player?.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }

    player = nil

    itemObservation?.cancel()
    cancellables.removeAll()
  }

  func closeSession() {
    Task {
      try? await sessionManager.closeSession(
        currentTime: mediaProgress.currentTime,
        isDownloaded: item?.isDownloaded ?? false
      )
    }
  }

  private func syncPlayback() {
    if WCSession.default.isReachable, WCSession.default.isPaired {
      watchConnectivity.sendPlaybackState(
        isPlaying: isPlaying,
        progress: playbackProgress.progress,
        current: playbackProgress.current,
        remaining: playbackProgress.remaining,
        total: playbackProgress.total,
        totalTimeRemaining: playbackProgress.totalTimeRemaining,
        bookID: id,
        title: title,
        author: author,
        coverURL: coverURL,
        playbackSpeed: speed.playbackSpeed
      )
    }

    savePlaybackStateToWidget()
  }

  private func savePlaybackStateToWidget() {
    guard let item else { return }

    let state = PlaybackState(
      bookID: item.bookID,
      title: item.title,
      author: item.authorNames,
      coverURL: item.coverURL,
      currentTime: playbackProgress.total - playbackProgress.totalTimeRemaining,
      duration: playbackProgress.total,
      isPlaying: isPlaying
    )

    if let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS"),
      let data = try? JSONEncoder().encode(state)
    {
      sharedDefaults.set(data, forKey: "playbackState")
      WidgetCenter.shared.reloadAllTimelines()
    }
  }
}
