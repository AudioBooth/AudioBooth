import API
import AVFoundation
import AVKit
import Combine
import MediaPlayer
import Models
import Nuke
import SwiftData
import SwiftUI
import WatchConnectivity

final class BookPlayerModel: BookPlayer.Model, ObservableObject {
  private let audiobookshelf = Audiobookshelf.shared

  private var player: AVPlayer?

  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  private var item: LocalBook?
  private var session: Session?
  private var itemObservation: Task<Void, Never>?
  private var mediaProgress: MediaProgress
  private var timerSecondsCounter = 0
  private var pendingPlay: Bool = false

  private var lastPlaybackAt: Date?
  private var lastSyncAt = Date()

  private let downloadManager = DownloadManager.shared
  private let watchConnectivity = WatchConnectivityManager.shared

  private var cover: UIImage?

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
      playbackProgress: PlaybackProgressViewModel()
    )

    setupDownloadStateBinding()
    onLoad()
  }

  init(_ item: LocalBook) {
    self.item = item
    do {
      self.mediaProgress = try MediaProgress.getOrCreate(for: item.bookID)
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
      playbackProgress: PlaybackProgressViewModel()
    )

    setupDownloadStateBinding()
    onLoad()
  }

  override func onTogglePlaybackTapped() {
    guard let player = player, player.status == .readyToPlay else {
      pendingPlay = true
      return
    }

    if isPlaying {
      player.rate = 0
    } else {
      player.rate = speed.playbackSpeed
    }
  }

  override func onSkipForwardTapped() {
    guard let player = player else { return }
    let currentTime = player.currentTime()
    let newTime = CMTimeAdd(currentTime, CMTime(seconds: 30, preferredTimescale: 1))
    player.seek(to: newTime)
  }

  override func onSkipBackwardTapped() {
    guard let player = player else { return }
    let currentTime = player.currentTime()
    let newTime = CMTimeSubtract(currentTime, CMTime(seconds: 30, preferredTimescale: 1))
    let zeroTime = CMTime(seconds: 0, preferredTimescale: 1)
    player.seek(to: CMTimeMaximum(newTime, zeroTime))
  }

  override func onDownloadTapped() {
    guard let item = item else { return }

    switch downloadState {
    case .downloading:
      downloadState = .notDownloaded
      downloadManager.cancelDownload(for: id)

    case .downloaded:
      downloadManager.deleteDownload(for: id)

    case .notDownloaded:
      downloadState = .downloading(progress: 0)
      downloadManager.startDownload(for: item.bookID)
    }
  }
}

extension BookPlayerModel {
  private func setupSession() async throws {
    print("Fetching session from server...")

    let audiobookshelfSession = try await audiobookshelf.sessions.start(
      itemID: id,
      forceTranscode: false
    )

    if audiobookshelfSession.currentTime > mediaProgress.currentTime {
      mediaProgress.currentTime = audiobookshelfSession.currentTime
      print("Using server currentTime for cross-device sync: \(audiobookshelfSession.currentTime)s")

      if let player = self.player {
        let seekTime = CMTime(seconds: audiobookshelfSession.currentTime, preferredTimescale: 1000)
        player.seek(to: seekTime) { _ in
          print("Seeked to server position")
        }
      }
    }

    if let item {
      self.session = Session(from: audiobookshelfSession)
      item.chapters = audiobookshelfSession.chapters?.map(Chapter.init) ?? []

      try? MediaProgress.updateProgress(
        for: item.bookID,
        currentTime: mediaProgress.currentTime,
        timeListened: mediaProgress.timeListened,
        duration: item.duration,
        progress: mediaProgress.currentTime / item.duration
      )
      print("Updated session with chapters")
    } else {
      let newItem = LocalBook(from: audiobookshelfSession.libraryItem)
      item = newItem
      self.session = Session(from: audiobookshelfSession)
      try? item?.save()
      print("Created new item from session")
    }

    print("Session setup completed successfully")
  }

  private func setupAudioPlayer() async throws -> AVPlayer {
    guard let item else {
      throw Audiobookshelf.AudiobookshelfError.networkError("No item available")
    }

    let playerItem: AVPlayerItem

    let tracks = item.orderedTracks
    if tracks.count > 1 {
      playerItem = try await createCompositionPlayerItem(from: tracks)
      print("Created composition with \(tracks.count) tracks")
    } else {
      guard let track = item.track(at: 0) else {
        print("Failed to get track at time 0")
        Toast(error: "Failed to get track").show()
        isLoading = false
        PlayerManager.shared.clearCurrent()
        throw Audiobookshelf.AudiobookshelfError.networkError("Failed to get track")
      }

      let trackURL = session?.url(for: track) ?? track.localPath
      guard let trackURL else {
        print("No URL available for track")
        Toast(error: "Failed to get streaming URL").show()
        isLoading = false
        PlayerManager.shared.clearCurrent()
        throw Audiobookshelf.AudiobookshelfError.networkError("Failed to get track URL")
      }

      playerItem = AVPlayerItem(url: trackURL)
    }

    let player = AVPlayer(playerItem: playerItem)
    self.player = player

    return player
  }

  private func configurePlayerComponents(player: AVPlayer) {
    configureAudioSession()
    setupRemoteCommandCenter()
    setupPlayerObservers()
    setupTimeObserver()

    speed = SpeedPickerSheetViewModel(player: player)
    let timerViewModel = TimerPickerSheetViewModel()
    timerViewModel.setPlayer(player)
    timer = timerViewModel

    if let sessionChapters = item?.orderedChapters, !sessionChapters.isEmpty {
      chapters = ChapterPickerSheetViewModel(chapters: sessionChapters, player: player)
      timer.maxRemainingChapters = sessionChapters.count - 1
      print("Loaded \(sessionChapters.count) chapters from play session info")
    } else {
      chapters = nil
      print("No chapters available in play session info")
    }

    if let playbackProgress = playbackProgress as? PlaybackProgressViewModel {
      let totalDuration = item?.orderedTracks.reduce(0.0) { $0 + $1.duration }
      playbackProgress.configure(
        player: player,
        chapters: chapters,
        totalDuration: totalDuration
      )
    }
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
    Toast(error: "Failed to setup audio player").show()
    isLoading = false
    PlayerManager.shared.clearCurrent()
  }

  private func checkForExistingLocalBook() {
    guard item == nil else { return }

    do {
      if let existingItem = try LocalBook.fetch(bookID: id) {
        self.item = existingItem
        print("Found existing progress: \(mediaProgress.currentTime)s")
      }
    } catch {
      print("Failed to fetch local book item: \(error)")
      Toast(error: "Failed to load playback progress").show()
    }
  }

  private func onLoad() {
    Task {
      isLoading = true

      checkForExistingLocalBook()
      loadCover()

      let isDownloaded = item?.isDownloaded ?? false

      do {
        if isDownloaded {
          print("Book is downloaded, loading local files instantly")
          let progress = try? MediaProgress.fetch(bookID: item?.bookID ?? id)
          if let cachedCurrentTime = progress?.currentTime, cachedCurrentTime > 0 {
            mediaProgress.currentTime = cachedCurrentTime
            print("Using cached currentTime: \(cachedCurrentTime)s")
          }

          let player = try await setupAudioPlayer()
          configurePlayerComponents(player: player)
          seekToLastPosition(player: player)

          isLoading = false
          sendWatchUpdate()

          if pendingPlay {
            player.rate = speed.playbackSpeed
            pendingPlay = false
          }

          Task {
            do {
              try await setupSession()
            } catch {
              print("Background session fetch failed: \(error)")
            }
          }
        } else {
          print("Book not downloaded, fetching session first")
          try await setupSession()

          guard item != nil else {
            throw Audiobookshelf.AudiobookshelfError.networkError("Failed to obtain session")
          }

          let player = try await setupAudioPlayer()
          configurePlayerComponents(player: player)
          seekToLastPosition(player: player)

          isLoading = false
          sendWatchUpdate()

          if pendingPlay {
            player.rate = speed.playbackSpeed
            pendingPlay = false
          }
        }
      } catch {
        handleLoadError(error)
      }
    }
  }

  func loadCover() {
    Task {
      do {
        let request = ImageRequest(url: coverURL)
        cover = try await ImagePipeline.shared.image(for: request)
      } catch {
        print("Failed to load cover image for now playing: \(error)")
      }
    }
  }

  private func setupDownloadStateBinding() {
    guard let item = item else { return }

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
        self?.downloadState = downloadState
      }
      .store(in: &cancellables)

    itemObservation = Task { [weak self] in
      for await updatedItem in LocalBook.observe(where: \.bookID, equals: item.bookID) {
        guard !Task.isCancelled, let self = self else { continue }

        self.item = updatedItem

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
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay])

      if !audioSession.isOtherAudioPlaying {
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
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

    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] =
      playbackProgress.current + playbackProgress.remaining

    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackProgress.current
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

    if let cover {
      nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cover.size) { _ in
        return cover
      }
    }

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
            self?.recoveryAttempts = 0
            let duration = currentItem.duration
            if duration.isValid && !duration.isIndefinite {
            }
          case .failed:
            self?.isLoading = false
            let errorMessage = currentItem.error?.localizedDescription ?? "Unknown error"
            print("Player item failed: \(errorMessage)")
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
          print("Playback stalled - attempting recovery")
          self?.handleStreamFailure(error: nil)
        }
        .store(in: &cancellables)

      NotificationCenter.default.publisher(
        for: .AVPlayerItemFailedToPlayToEndTime, object: currentItem
      )
      .receive(on: DispatchQueue.main)
      .sink { [weak self] notification in
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        print("Failed to play to end: \(error?.localizedDescription ?? "Unknown")")
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
      print("Audio interruption began")

    case .ended:
      guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
        return
      }

      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      if options.contains(.shouldResume) {
        print("Audio interruption ended - resuming playback")
        player?.rate = speed.playbackSpeed
      } else {
        print("Audio interruption ended - not resuming")
      }

    @unknown default:
      break
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
          self.timer.maxRemainingChapters = model.chapters.count - model.currentIndex - 1

          if case .chapters(let chapters) = self.timer.current {
            if previous < model.currentIndex {
              if chapters > 1 {
                self.timer.current = .chapters(chapters - 1)
              } else {
                self.player?.pause()
                self.timer.current = .none
              }
            }
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
          self.sendWatchUpdate()
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
      let trackURL = session?.url(for: track) ?? track.localPath
      guard let trackURL else {
        print("Skipping track \(track.index) - no URL")
        continue
      }

      let asset = AVURLAsset(url: trackURL)
      let assetTracks = try await asset.loadTracks(withMediaType: .audio)

      guard let assetAudioTrack = assetTracks.first else {
        print("Skipping track \(track.index) - no audio track")
        continue
      }

      let trackDuration = CMTime(seconds: track.duration, preferredTimescale: 600)
      let timeRange = CMTimeRange(start: .zero, duration: trackDuration)

      do {
        try audioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: currentTime)
        currentTime = CMTimeAdd(currentTime, trackDuration)
        print("Added track \(track.index) at time \(CMTimeGetSeconds(currentTime))")
      } catch {
        print("Failed to insert track \(track.index): \(error)")
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
    guard let player = self.player,
      let item
    else {
      print("Cannot refresh player - missing player or item")
      return
    }

    print("Refreshing player to use local files")

    let currentTime = player.currentTime()
    let wasPlaying = isPlaying

    player.pause()

    Task {
      do {
        let playerItem: AVPlayerItem

        let tracks = item.orderedTracks
        if tracks.count > 1 {
          playerItem = try await createCompositionPlayerItem(from: tracks)
          print("Recreated composition with local files for \(tracks.count) tracks")
        } else {
          guard let track = item.track(at: 0) else {
            print("Failed to get track at time 0")
            Toast(error: "Failed to get track").show()
            return
          }

          let trackURL = session?.url(for: track) ?? track.localPath
          guard let trackURL else {
            print("No URL available for track")
            Toast(error: "Failed to get streaming URL").show()
            return
          }

          playerItem = AVPlayerItem(url: trackURL)
          print("Using URL: \(trackURL)")
        }

        player.replaceCurrentItem(with: playerItem)

        player.seek(to: currentTime) { _ in
          if wasPlaying {
            player.play()
          }
          print("Restored playback position and state after switching to local files")
        }

      } catch {
        print("Failed to refresh player for local playback: \(error)")
        Toast(error: "Failed to switch to downloaded files").show()
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
        mediaProgress.timeListened += timeListened
        mediaProgress.lastPlayedAt = Date()
        syncSessionProgress()
      }
      lastPlaybackAt = nil

      markAsFinishedIfNeeded()
    }

    try? mediaProgress.save()
    try? item?.save()

    sendWatchUpdate()
  }

  private func markAsFinishedIfNeeded() {
    guard !mediaProgress.isFinished else { return }
    guard let chaptersModel = chapters as? ChapterPickerSheetViewModel else { return }

    let isOnLastChapter = chaptersModel.currentIndex == chaptersModel.chapters.count - 1
    guard isOnLastChapter else { return }

    mediaProgress.isFinished = true
    mediaProgress.progress = 1.0
    try? mediaProgress.save()

    Task {
      do {
        try await Audiobookshelf.shared.libraries.updateBookFinishedStatus(
          bookID: id, isFinished: true)
        print("Successfully marked book as finished on server")
      } catch {
        print("Failed to update book finished status on server: \(error)")
      }
    }
  }

  private func syncSessionProgress() {
    guard let session = self.session else { return }

    let now = Date()

    guard mediaProgress.timeListened >= 20, now.timeIntervalSince(lastSyncAt) >= 10 else { return }

    lastSyncAt = now

    Task {
      do {
        try await audiobookshelf.sessions.sync(
          session.id,
          timeListened: mediaProgress.timeListened,
          currentTime: mediaProgress.currentTime
        )

        mediaProgress.timeListened = 0
      } catch {
        print("Failed to sync session progress: \(error)")

        if isSessionNotFoundError(error) {
          print("Session not found (404) - triggering recovery")
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

  private func updateMediaProgress() {
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

        syncSessionProgress()
      } catch {
        print("Failed to update playback progress: \(error)")
        Toast(error: "Failed to update playback progress").show()
      }
    }
  }

  private func handleStreamFailure(error: Error?) {
    guard !isRecovering else {
      print("Already recovering, skipping duplicate recovery attempt")
      return
    }

    guard recoveryAttempts < maxRecoveryAttempts else {
      print("Max recovery attempts reached, giving up")
      let errorMessage = error?.localizedDescription ?? "Stream unavailable"
      Toast(error: "Playback failed: \(errorMessage)").show()
      PlayerManager.shared.clearCurrent()
      return
    }

    let isDownloaded = item?.isDownloaded ?? false
    guard !isDownloaded else {
      print("Book is downloaded, cannot recover from stream failure")
      return
    }

    isRecovering = true
    recoveryAttempts += 1

    print("Stream failure detected (attempt \(recoveryAttempts)/\(maxRecoveryAttempts))")

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

    player.pause()
    isLoading = true
    Toast(message: "Reconnecting...").show()

    let delay = min(pow(2.0, Double(recoveryAttempts - 1)), 8.0)
    if delay > 0 {
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    do {
      try await setupSession()

      guard let item else {
        throw Audiobookshelf.AudiobookshelfError.networkError("Failed to recreate session")
      }

      let playerItem: AVPlayerItem

      let tracks = item.orderedTracks
      if tracks.count > 1 {
        playerItem = try await createCompositionPlayerItem(from: tracks)
        print("Recreated composition with \(tracks.count) tracks after recovery")
      } else {
        guard let track = item.track(at: 0) else {
          throw Audiobookshelf.AudiobookshelfError.networkError("Failed to get track")
        }

        let trackURL = session?.url(for: track) ?? track.localPath
        guard let trackURL else {
          throw Audiobookshelf.AudiobookshelfError.networkError("Failed to get track URL")
        }

        playerItem = AVPlayerItem(url: trackURL)
      }

      player.replaceCurrentItem(with: playerItem)
      setupPlayerObservers()

      let rewindTime = CMTimeSubtract(currentTime, CMTime(seconds: 5, preferredTimescale: 1000))
      let seekTime = CMTimeMaximum(rewindTime, .zero)

      player.seek(to: seekTime) { [weak self] _ in
        guard let self else { return }

        self.isLoading = false
        self.isRecovering = false

        if wasPlaying {
          player.rate = self.speed.playbackSpeed
        }

        print(
          "Successfully recovered stream at position: \(CMTimeGetSeconds(seekTime))s (rewound 5s)"
        )
        Toast(message: "Reconnected").show()
      }

    } catch {
      print("Failed to recover session: \(error)")

      isLoading = false
      isRecovering = false

      if recoveryAttempts < maxRecoveryAttempts {
        handleStreamFailure(error: error)
      } else {
        Toast(error: "Unable to reconnect. Please try again later.").show()
        PlayerManager.shared.clearCurrent()
      }
    }
  }

  func stopPlayer() {
    player?.rate = 0
    player = nil

    itemObservation?.cancel()
    timeObserver = nil
    cancellables.removeAll()
  }

  func closeSession() {
    guard let session = self.session else {
      print("Session already closed or no session to close")
      return
    }

    Task {
      if mediaProgress.timeListened > 0 {
        do {
          try await audiobookshelf.sessions.sync(
            session.id,
            timeListened: mediaProgress.timeListened,
            currentTime: mediaProgress.currentTime
          )

          mediaProgress.timeListened = 0
        } catch {
          print("Failed to sync session progress: \(error)")
        }
      }

      do {
        try await audiobookshelf.sessions.close(session.id)
        print("Successfully closed session: \(session.id)")
      } catch {
        print("Failed to close session: \(error)")
      }
    }
  }

  private func sendWatchUpdate() {
    guard WCSession.default.isReachable, WCSession.default.isPaired else { return }

    let playbackProgress = self.playbackProgress
    let actualIsPlaying = player?.rate ?? 0 > 0

    watchConnectivity.sendPlaybackState(
      isPlaying: actualIsPlaying,
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

}
