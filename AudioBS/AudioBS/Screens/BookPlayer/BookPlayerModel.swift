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
      author: item.author,
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
      downloadManager.cancelDownload(for: id)
    case .downloaded:
      downloadManager.deleteDownload(for: id)
    case .notDownloaded:
      downloadManager.startDownload(for: item.bookID)
    }
  }
}

extension BookPlayerModel {
  private func setupSessionInfo() async throws {
    // If book is already downloaded, use local files (session is optional)
    if let existingItem = item, existingItem.isDownloaded {
      print("Book is downloaded, using local files (session optional)")
      print("Item has \(existingItem.tracks?.count ?? 0) tracks")

      let progress = try? MediaProgress.fetch(bookID: existingItem.bookID)
      let cachedCurrentTime = progress?.currentTime ?? 0
      if cachedCurrentTime > 0 {
        mediaProgress.currentTime = cachedCurrentTime
        print("Using existing currentTime: \(cachedCurrentTime)s")
      }

      // Try to fetch session for streaming URLs, but don't fail if it doesn't work
      do {
        print("Attempting to fetch session for potential streaming...")
        let audiobookshelfSession = try await audiobookshelf.sessions.start(
          itemID: id,
          forceTranscode: false
        )
        self.session = Session(from: audiobookshelfSession)

        if audiobookshelfSession.currentTime > mediaProgress.currentTime {
          mediaProgress.currentTime = audiobookshelfSession.currentTime
          print(
            "Using server currentTime for cross-device sync: \(audiobookshelfSession.currentTime)s")
        }

        print("Session available for streaming if needed")
      } catch {
        print("Session fetch failed, will use local files only: \(error)")
      }

      return
    }

    // Book is not downloaded, session is required
    do {
      print("Attempting to fetch fresh session from server...")

      let audiobookshelfSession: PlaySession
      audiobookshelfSession = try await audiobookshelf.sessions.start(
        itemID: id,
        forceTranscode: false
      )

      if audiobookshelfSession.currentTime > mediaProgress.currentTime {
        mediaProgress.currentTime = audiobookshelfSession.currentTime
        print(
          "Using server currentTime for cross-device sync: \(audiobookshelfSession.currentTime)s")
      }

      if let item {
        self.session = Session(from: audiobookshelfSession)
        item.chapters = audiobookshelfSession.chapters?.map(Chapter.init)

        try? MediaProgress.updateProgress(
          for: item.bookID,
          currentTime: mediaProgress.currentTime,
          timeListened: mediaProgress.timeListened,
          duration: item.duration,
          progress: mediaProgress.currentTime / item.duration
        )
        print("Merged fresh session with existing session to preserve local files")
      } else {
        let newItem = LocalBook(from: audiobookshelfSession.libraryItem)
        item = newItem
        self.session = Session(from: audiobookshelfSession)
        try? item?.save()
      }

      print("Successfully fetched fresh session from server")

    } catch {
      print("Failed to fetch fresh session: \(error)")
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Cannot play without network connection or downloaded files")
    }

    guard item != nil else {
      throw Audiobookshelf.AudiobookshelfError.networkError("Failed to obtain session info")
    }
  }

  private func setupAudioPlayer() async throws -> AVPlayer {
    guard let item else {
      throw Audiobookshelf.AudiobookshelfError.networkError("No item available")
    }

    let playerItem: AVPlayerItem

    if let tracks = item.orderedTracks, tracks.count > 1 {
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

    if let sessionChapters = item?.orderedChapters {
      chapters = ChapterPickerSheetViewModel(chapters: sessionChapters, player: player)
      timer.maxRemainingChapters = sessionChapters.count - 1
      print("Loaded \(sessionChapters.count) chapters from play session info")
    } else {
      chapters = nil
      print("No chapters available in play session info")
    }

    if let playbackProgress = playbackProgress as? PlaybackProgressViewModel {
      let totalDuration = item?.orderedTracks?.reduce(0.0) { $0 + $1.duration }
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
      print("Failed to fetch existing recently played item: \(error)")
      Toast(error: "Failed to load playback progress").show()
    }
  }

  private func onLoad() {
    Task {
      isLoading = true

      checkForExistingLocalBook()
      loadCover()

      do {
        try await setupSessionInfo()
        let player = try await setupAudioPlayer()
        configurePlayerComponents(player: player)
        seekToLastPosition(player: player)
        saveLocalBook()

        isLoading = false
        sendWatchUpdate()

        if pendingPlay {
          player.rate = speed.playbackSpeed
          pendingPlay = false
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
    Publishers.CombineLatest(downloadManager.$downloads, downloadManager.$downloadProgress)
      .map { [weak self] downloads, progress in
        guard let item = self?.item else { return .notDownloaded }

        if downloads[item.bookID] == true {
          let downloadProgress = progress[item.bookID] ?? 0.0
          return .downloading(progress: downloadProgress)
        }

        return item.isDownloaded ? .downloaded : .notDownloaded
      }
      .sink { [weak self] downloadState in
        self?.downloadState = downloadState
      }
      .store(in: &cancellables)

    if let bookID = item?.bookID {
      itemObservation = Task { [weak self] in
        for await updatedItem in LocalBook.observe(where: \.bookID, equals: bookID) {
          guard !Task.isCancelled, let self = self else { continue }

          self.item = updatedItem

          // Re-evaluate download state with updated item
          if downloadManager.downloads[updatedItem.bookID] == true {
            let progress = downloadManager.downloadProgress[updatedItem.bookID] ?? 0.0
            self.downloadState = .downloading(progress: progress)
          } else {
            self.downloadState =
              updatedItem.isDownloaded ? .downloaded : .notDownloaded
          }

          if updatedItem.isDownloaded, self.isPlayerUsingRemoteURL() {
            self.refreshPlayerForLocalPlayback()
          }
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
            let duration = currentItem.duration
            if duration.isValid && !duration.isIndefinite {
            }
          case .failed:
            self?.isLoading = false
            let errorMessage = currentItem.error?.localizedDescription ?? "Unknown error"
            print("Player item failed: \(errorMessage)")
            Toast(error: "Audio playback failed: \(errorMessage)").show()
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
          self.updateRecentlyPlayedProgress()
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
    guard let item else {
      throw Audiobookshelf.AudiobookshelfError.compositionError("No item available")
    }

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

  private func saveLocalBook() {
    guard let item else {
      return
    }

    do {
      try item.save()
    } catch {
      print("Failed to save recently played item: \(error)")
      Toast(error: "Failed to save playback progress").show()
    }
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

        if let tracks = item.orderedTracks, tracks.count > 1 {
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
        syncSessionProgress()
      }
      lastPlaybackAt = nil
    }
    try? mediaProgress.save()

    sendWatchUpdate()
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
        Toast(error: "Failed to update playback progress").show()
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
