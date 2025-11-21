import AVFoundation
import Combine
import Foundation
import MediaPlayer
import OSLog

final class BookPlayerModel: PlayerView.Model {
  let bookID: String

  private let connectivityManager = WatchConnectivityManager.shared
  private let localStorage = LocalBookStorage.shared
  private var player: AVPlayer?
  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()

  private(set) var book: WatchBook
  private var localBook: WatchBook?
  private var sessionID: String?
  private var currentTrackIndex: Int = 0
  private var currentChapterIndex: Int = 0
  private var totalDuration: Double = 0
  private var lastProgressReportTime: Date?
  private var progressSaveCounter: Int = 0

  init(book: WatchBook) {
    self.bookID = book.id

    if let downloaded = localStorage.books.first(where: { $0.id == book.id }),
      downloaded.isDownloaded
    {
      self.localBook = downloaded
      var mergedBook = downloaded
      if downloaded.coverURL == nil {
        mergedBook.coverURL = book.coverURL
      }
      self.book = mergedBook
    } else {
      self.book = book
    }

    self.totalDuration = self.book.duration

    super.init(
      isPlaying: false,
      isReadyToPlay: false,
      isLocal: localBook != nil,
      progress: self.book.progress,
      current: self.book.currentTime,
      remaining: self.book.timeRemaining,
      totalTimeRemaining: self.book.timeRemaining,
      title: self.book.title,
      author: self.book.authorName,
      coverURL: self.book.coverURL,
      chapters: nil
    )

    setupOptionsModel()
    setupChapters()
    load()
  }

  private func setupOptionsModel() {
    let optionsModel = BookPlayerOptionsModel(
      playerModel: self,
      hasChapters: !book.chapters.isEmpty
    )
    options = optionsModel
  }

  private func setupChapters() {
    guard !book.chapters.isEmpty else { return }

    let chapterModels = BookChapterPickerModel(
      chapters: book.chapters,
      playerModel: self,
      currentIndex: 0
    )
    chapters = chapterModels
    options.hasChapters = true
  }

  private func load() {
    if localBook != nil {
      Task {
        await setupPlayerWithLocalBook()
        startSessionInBackground()
      }
    } else {
      Task {
        await startSessionAndPlay()
      }
    }
  }

  private func startSessionInBackground() {
    Task {
      guard let info = await connectivityManager.startSession(bookID: bookID) else {
        AppLogger.player.warning("Failed to start session for progress reporting")
        return
      }
      self.sessionID = info.sessionID
      AppLogger.player.info("Session started for progress reporting: \(info.sessionID ?? "nil")")
    }
  }

  private func startSessionAndPlay() async {
    isLoading = true

    AppLogger.player.info(
      "Loading book info for \(self.bookID), isReachable: \(self.connectivityManager.isReachable)"
    )

    guard let info = await connectivityManager.startSession(bookID: bookID) else {
      AppLogger.player.error("Failed to start session for streaming")
      isLoading = false
      return
    }

    AppLogger.player.info(
      "Got book info: \(info.tracks.count) tracks, \(info.chapters.count) chapters")

    self.sessionID = info.sessionID
    self.book = info

    if !info.chapters.isEmpty && chapters == nil {
      let chapterModels = BookChapterPickerModel(
        chapters: info.chapters,
        playerModel: self,
        currentIndex: 0
      )
      chapters = chapterModels
      options.hasChapters = true
    }

    await setupPlayerWithStreamingBook(info)
  }

  private func setupPlayerWithLocalBook() async {
    guard let localBook = localBook else { return }

    isLoading = true

    guard let track = localBook.track(at: book.currentTime) else {
      AppLogger.player.error("Failed to find track at time \(self.book.currentTime)")
      isLoading = false
      return
    }

    guard let trackURL = localBook.localURL(for: track) else {
      AppLogger.player.error(
        "Failed to get local URL for track \(track.index), relativePath: \(track.relativePath ?? "nil")"
      )
      isLoading = false
      return
    }

    guard FileManager.default.fileExists(atPath: trackURL.path) else {
      AppLogger.player.error("Track file does not exist at: \(trackURL.path)")
      isLoading = false
      return
    }

    AppLogger.player.info(
      "Track found: index=\(track.index), duration=\(track.duration), url=\(trackURL.path)")

    currentTrackIndex = track.index

    await configureAudioSession()

    await MainActor.run {
      let playerItem = AVPlayerItem(url: trackURL)
      let player = AVPlayer(playerItem: playerItem)
      self.player = player

      setupPlayerObservers()
      setupTimeObserver()
      setupRemoteCommandCenter()

      let trackStartTime = calculateTrackStartTime(trackIndex: track.index)
      let seekTime = book.currentTime - trackStartTime

      if seekTime > 0 {
        player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 1000))
      }

      isLoading = false
      AppLogger.player.info("Local player ready for \(self.bookID)")
    }
  }

  private func setupPlayerWithStreamingBook(_ info: WatchBook) async {
    guard let track = findTrack(for: book.currentTime, in: info.tracks),
      let trackURL = track.url
    else {
      AppLogger.player.error("Failed to get track or URL")
      isLoading = false
      return
    }

    currentTrackIndex = track.index
    AppLogger.player.info("Track URL: \(trackURL.absoluteString)")

    await configureAudioSession()

    await MainActor.run {
      let playerItem = AVPlayerItem(url: trackURL)
      playerItem.audioTimePitchAlgorithm = .timeDomain

      let player = AVPlayer(playerItem: playerItem)
      self.player = player

      setupPlayerObservers()
      setupTimeObserver()
      setupRemoteCommandCenter()

      let trackStartTime = calculateTrackStartTime(trackIndex: track.index)
      let seekTime = book.currentTime - trackStartTime

      if seekTime > 0 {
        player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 1000))
      }

      AppLogger.player.info(
        "Streaming player setup complete for \(self.bookID), waiting for ready state")
    }
  }

  private func configureAudioSession() async {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(
        .playback,
        mode: .spokenAudio,
        policy: .longFormAudio,
        options: []
      )
      try await audioSession.activate()
      AppLogger.player.info("Audio session activated")
    } catch {
      AppLogger.player.error("Failed to configure audio session: \(error)")
    }
  }

  private func findTrack(for time: Double, in tracks: [WatchTrack]) -> WatchTrack? {
    let sortedTracks = tracks.sorted { $0.index < $1.index }
    var accumulatedTime: Double = 0

    for track in sortedTracks {
      if time >= accumulatedTime && time < accumulatedTime + track.duration {
        return track
      }
      accumulatedTime += track.duration
    }

    return sortedTracks.first
  }

  private func calculateTrackStartTime(trackIndex: Int) -> Double {
    let tracks = localBook?.tracks ?? book.tracks
    let sortedTracks = tracks.sorted { $0.index < $1.index }
    var startTime: Double = 0

    for track in sortedTracks {
      if track.index >= trackIndex {
        break
      }
      startTime += track.duration
    }

    return startTime
  }

  override func togglePlayback() {
    guard let player else { return }

    if isPlaying {
      player.rate = 0
    } else {
      player.rate = 1.0
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

  override func stop() {
    if let timeObserver = timeObserver, let player = player {
      player.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
    player?.pause()
    saveProgress(currentTime: current)
    player = nil
  }

  override func onDownloadTapped() {
    guard let options = options as? BookPlayerOptionsModel else { return }
    options.onDownloadTapped()
  }

  func switchToLocalPlayback(_ book: WatchBook) {
    self.localBook = book
    self.isLocal = true
    AppLogger.player.info("Switched to local playback for \(self.bookID)")
  }

  func clearLocalPlayback() {
    self.localBook = nil
    self.isLocal = false
  }

  func seekToChapter(at index: Int) {
    let chapters = book.chapters
    guard index >= 0, index < chapters.count else { return }

    let chapter = chapters[index]
    let tracks = localBook?.tracks ?? book.tracks

    guard let track = findTrack(for: chapter.start, in: tracks) else { return }

    if track.index != currentTrackIndex {
      loadTrack(track, seekTo: chapter.start)
    } else if let player = player {
      let trackStartTime = calculateTrackStartTime(trackIndex: track.index)
      let seekTime = chapter.start - trackStartTime
      player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 1000))
    }

    currentChapterIndex = index
    self.chapters?.currentIndex = index

    if isLocal {
      saveProgress(currentTime: chapter.start)
    }
    reportProgressNow(currentTime: chapter.start)
  }

  private func loadTrack(_ track: WatchTrack, seekTo globalTime: Double) {
    let trackURL: URL
    if let localBook = localBook,
      let localTrack = localBook.tracks.first(where: { $0.index == track.index }),
      let localURL = localBook.localURL(for: localTrack)
    {
      trackURL = localURL
    } else if let url = track.url {
      trackURL = url
    } else {
      return
    }

    let wasPlaying = isPlaying
    player?.pause()

    let playerItem = AVPlayerItem(url: trackURL)
    player?.replaceCurrentItem(with: playerItem)

    currentTrackIndex = track.index

    let trackStartTime = calculateTrackStartTime(trackIndex: track.index)
    let seekTime = globalTime - trackStartTime

    player?.seek(to: CMTime(seconds: max(0, seekTime), preferredTimescale: 1000)) { [weak self] _ in
      if wasPlaying {
        self?.player?.rate = 1.0
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

    commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 30)]
    commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 30)]

    commandCenter.skipForwardCommand.addTarget { [weak self] _ in
      self?.skipForward()
      return .success
    }

    commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
      self?.skipBackward()
      return .success
    }
  }

  private func setupPlayerObservers() {
    guard let player else { return }

    player.publisher(for: \.rate)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] rate in
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
            AppLogger.player.info("Player item ready to play")
          case .failed:
            self?.isLoading = false
            self?.isReadyToPlay = false
            if let error = currentItem.error {
              AppLogger.player.error("Player item failed: \(error.localizedDescription)")
            } else {
              AppLogger.player.error("Player item failed with unknown error")
            }
          case .unknown:
            self?.isLoading = true
            self?.isReadyToPlay = false
          @unknown default:
            break
          }
        }
        .store(in: &cancellables)
    }
  }

  private func setupTimeObserver() {
    guard let player else { return }

    let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      guard let self, time.isValid, !time.isIndefinite else { return }

      let trackTime = CMTimeGetSeconds(time)
      let trackStartTime = self.calculateTrackStartTime(trackIndex: self.currentTrackIndex)
      let globalTime = trackStartTime + trackTime

      self.current = globalTime
      self.remaining = max(0, self.totalDuration - globalTime)
      self.progress = self.totalDuration > 0 ? globalTime / self.totalDuration : 0
      self.totalTimeRemaining = self.remaining

      self.updateCurrentChapter(currentTime: globalTime)

      self.progressSaveCounter += 1

      if let sessionID = self.sessionID {
        let now = Date()
        if let lastReport = self.lastProgressReportTime {
          let timeSinceLastReport = now.timeIntervalSince(lastReport)
          if timeSinceLastReport >= 30 {
            self.connectivityManager.reportProgress(
              sessionID: sessionID,
              currentTime: globalTime,
              timeListened: timeSinceLastReport
            )
            self.lastProgressReportTime = now
          }
        } else {
          self.lastProgressReportTime = now
        }
      }

      if self.isLocal && self.progressSaveCounter % 60 == 0 {
        self.saveProgress(currentTime: globalTime)
      }
    }
  }

  private func updateCurrentChapter(currentTime: Double) {
    let chapters = book.chapters
    guard !chapters.isEmpty else {
      chapterTitle = nil
      return
    }

    for (index, chapter) in chapters.enumerated() {
      if currentTime >= chapter.start && currentTime < chapter.end {
        if currentChapterIndex != index {
          currentChapterIndex = index
          self.chapters?.currentIndex = index
        }

        chapterTitle = chapter.title
        chapterCurrent = currentTime - chapter.start
        chapterRemaining = chapter.end - currentTime
        let chapterDuration = chapter.end - chapter.start
        chapterProgress = chapterDuration > 0 ? (currentTime - chapter.start) / chapterDuration : 0
        return
      }
    }

    chapterTitle = nil
  }

  private func saveProgress(currentTime: Double) {
    localStorage.updateProgress(for: bookID, currentTime: currentTime)
  }

  private func reportProgressNow(currentTime: Double) {
    guard let sessionID = sessionID else { return }
    let now = Date()
    let timeListened = lastProgressReportTime.map { now.timeIntervalSince($0) } ?? 0
    connectivityManager.reportProgress(
      sessionID: sessionID,
      currentTime: currentTime,
      timeListened: timeListened
    )
    lastProgressReportTime = now
  }

  private func updateNowPlayingInfo() {
    var nowPlayingInfo = [String: Any]()
    nowPlayingInfo[MPMediaItemPropertyTitle] = title
    nowPlayingInfo[MPMediaItemPropertyArtist] = author
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = totalDuration
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = current
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  @MainActor
  deinit {
    if let timeObserver = timeObserver, let player = player {
      player.removeTimeObserver(timeObserver)
    }
    player?.pause()
    saveProgress(currentTime: current)
  }
}
