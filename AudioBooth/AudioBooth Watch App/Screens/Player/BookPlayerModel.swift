import AVFoundation
import Combine
import Foundation
import MediaPlayer
import OSLog
import WidgetKit

final class BookPlayerModel: PlayerView.Model {
  let bookID: String

  private let connectivityManager = WatchConnectivityManager.shared
  private let localStorage = LocalBookStorage.shared
  private let audioPlayer = WatchAudioPlayer()
  private var cancellables = Set<AnyCancellable>()

  private(set) var book: WatchBook
  private var localBook: WatchBook?
  private var sessionID: String?
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
      playbackState: .loading,
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

    subscribeToPlayerEvents()
    setupProgressObserver()
    setupOptionsModel()
    setupChapters()
    load()
  }

  private func subscribeToPlayerEvents() {
    audioPlayer.events
      .receive(on: DispatchQueue.main)
      .sink { [weak self] event in
        self?.handlePlayerEvent(event)
      }
      .store(in: &cancellables)
  }

  private func handlePlayerEvent(_ event: WatchAudioPlayer.Event) {
    switch event {
    case .timeUpdate(let globalTime):
      current = globalTime
      remaining = max(0, totalDuration - globalTime)
      progress = totalDuration > 0 ? globalTime / totalDuration : 0
      totalTimeRemaining = remaining

      updateCurrentChapter(currentTime: globalTime)
      updateNowPlayingInfo()

      progressSaveCounter += 1
      reportProgressIfNeeded(currentTime: globalTime)

      if isLocal && progressSaveCounter % 60 == 0 {
        saveProgress(currentTime: globalTime)
      }

      if progressSaveCounter % 20 == 0 {
        updateComplicationState()
      }

    case .stateChanged(let state):
      switch state {
      case .playing:
        isPlaying = true
        updateComplicationState()
      case .paused:
        isPlaying = false
        updateComplicationState()
      case .ready:
        playbackState = .ready
      case .buffering:
        break
      case .stopped:
        isPlaying = false
      case .error:
        break
      }

    case .seek:
      break

    case .finished:
      isPlaying = false
      saveProgress(currentTime: current)
      updateComplicationState()

    case .stalled:
      break

    case .error(let error):
      handlePlaybackError(error)
    }
  }

  private func handlePlaybackError(_ error: Error?) {
    if localBook != nil {
      AppLogger.player.warning("Local playback failed, falling back to streaming.")
      Task {
        await handleCorruptedDownload()
      }
    } else {
      let isNetworkError: Bool
      if let error {
        let nsError = error as NSError
        isNetworkError = nsError.domain == NSURLErrorDomain || nsError.code == -1009
      } else {
        isNetworkError = false
      }
      playbackState = .error(retryable: isNetworkError)
      errorMessage = isNetworkError ? "Network error. Tap to retry." : "Playback failed."
    }
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
        await configureAudioSession()
        preparePlayerWithLocalBook()
        audioPlayer.resume(at: book.currentTime)
        setupRemoteCommandCenter()
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
    playbackState = .loading

    AppLogger.player.info(
      "Loading book info for \(self.bookID), isReachable: \(self.connectivityManager.isReachable)"
    )

    guard let info = await connectivityManager.startSession(bookID: bookID) else {
      AppLogger.player.error("Failed to start session for streaming")
      playbackState = .error(retryable: true)
      errorMessage = "Failed to connect. Tap to retry."
      return
    }

    AppLogger.player.info(
      "Got book info: \(info.tracks.count) tracks, \(info.chapters.count) chapters"
    )

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

    await configureAudioSession()

    audioPlayer.prepare(tracks: info.tracks) { track in
      track.url
    }
    audioPlayer.resume(at: book.currentTime)
    setupRemoteCommandCenter()
  }

  private func preparePlayerWithLocalBook() {
    guard let localBook else { return }

    audioPlayer.prepare(tracks: localBook.tracks) { track in
      localBook.localURL(for: track)
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

  override func togglePlayback() {
    if isPlaying {
      audioPlayer.pause()
    } else {
      syncToLatestKnownProgressIfNeeded()
      audioPlayer.resume()
    }
  }

  override func skipForward() {
    let newTime = min(current + 30, totalDuration)
    audioPlayer.seek(to: newTime)
  }

  override func skipBackward() {
    let newTime = max(current - 30, 0)
    audioPlayer.seek(to: newTime)
  }

  override func stop() {
    audioPlayer.stop()
    saveProgress(currentTime: current)
  }

  override func onDownloadTapped() {
    guard let options = options as? BookPlayerOptionsModel else { return }
    options.onDownloadTapped()
  }

  override func retry() {
    AppLogger.player.info("Retrying playback for \(self.bookID)")
    errorMessage = nil

    audioPlayer.stop()

    if localBook != nil {
      Task {
        await configureAudioSession()
        preparePlayerWithLocalBook()
        audioPlayer.resume(at: book.currentTime)
        setupRemoteCommandCenter()
        startSessionInBackground()
      }
    } else {
      Task {
        await startSessionAndPlay()
      }
    }
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

  private func handleCorruptedDownload() async {
    guard localBook != nil else { return }

    AppLogger.player.info("Cleaning up corrupted download for \(self.bookID)")

    audioPlayer.stop()

    DownloadManager.shared.deleteDownload(for: bookID)

    self.localBook = nil
    self.isLocal = false

    errorMessage = "Download was corrupted. Streaming instead."

    await startSessionAndPlay()
  }

  func seekToChapter(at index: Int) {
    let chapters = book.chapters
    guard index >= 0, index < chapters.count else { return }

    let chapter = chapters[index]

    audioPlayer.seek(to: chapter.start)

    currentChapterIndex = index
    self.chapters?.currentIndex = index

    if isLocal {
      saveProgress(currentTime: chapter.start)
    }
    reportProgressNow(currentTime: chapter.start)
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

  private func reportProgressIfNeeded(currentTime: Double) {
    guard let sessionID else { return }
    let now = Date()
    if let lastReport = lastProgressReportTime {
      let timeSinceLastReport = now.timeIntervalSince(lastReport)
      if timeSinceLastReport >= 30 || currentTime < 1.0 {
        connectivityManager.reportProgress(
          bookID: book.id,
          sessionID: sessionID,
          currentTime: currentTime,
          timeListened: timeSinceLastReport,
          duration: totalDuration
        )
        lastProgressReportTime = now
      }
    } else {
      lastProgressReportTime = now
    }
  }

  private func reportProgressNow(currentTime: Double) {
    guard let sessionID = sessionID else { return }
    let now = Date()
    let timeListened = lastProgressReportTime.map { now.timeIntervalSince($0) } ?? 0
    connectivityManager.reportProgress(
      bookID: book.id,
      sessionID: sessionID,
      currentTime: currentTime,
      timeListened: timeListened,
      duration: self.totalDuration
    )
    lastProgressReportTime = now
  }

  private func updateComplicationState() {
    let state = WatchComplicationState(
      bookTitle: book.title,
      progress: totalDuration > 0 ? current / totalDuration : 0,
      chapterProgress: chapterProgress > 0 ? chapterProgress : nil,
      currentTime: current,
      duration: totalDuration,
      isPlaying: isPlaying
    )
    WatchComplicationStorage.save(state)
    WidgetCenter.shared.reloadAllTimelines()
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

  private func setupProgressObserver() {
    connectivityManager.$progress
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.syncToLatestKnownProgressIfNeeded()
      }
      .store(in: &cancellables)

    syncToLatestKnownProgressIfNeeded()
  }

  private func syncToLatestKnownProgressIfNeeded() {
    guard
      !isPlaying,
      let latest = connectivityManager.progress[bookID],
      latest - current > 0.5
    else { return }

    current = latest

    let duration = max(totalDuration, book.duration, 1)
    remaining = max(0, duration - latest)
    progress = min(1, max(0, latest / duration))
    totalTimeRemaining = remaining

    audioPlayer.seek(to: latest)
  }

  @MainActor
  deinit {
    audioPlayer.stop()
    saveProgress(currentTime: current)
  }
}
