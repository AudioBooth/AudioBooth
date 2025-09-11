import AVFoundation
import AVKit
import Audiobookshelf
import Combine
import MediaPlayer
import Nuke
import SwiftData
import SwiftUI

@MainActor
final class BookPlayerModel: BookPlayer.Model, ObservableObject {
  private let audiobookshelf = Audiobookshelf.shared
  private var userProgressService = UserProgressService.shared

  private var player: AVPlayer?

  private var timeObserver: Any?
  private var cancellables = Set<AnyCancellable>()
  private var item: RecentlyPlayedItem?
  private var timerSecondsCounter = 0
  private var lastPlaybackTime: Date?

  private let downloadManager = DownloadManager.shared

  private var cover: UIImage?

  init(_ book: Book) {
    self.item = nil

    super.init(
      id: book.id,
      title: book.title,
      author: book.authorName,
      coverURL: book.coverURL,
      speed: SpeedPickerSheet.Model(),
      timer: TimerPickerSheet.Model(),
      playbackProgress: PlaybackProgressViewModel()
    )

    if let progress = userProgressService.progressByBookID[book.id] {
      self.currentTime = progress.currentTime
    }

    setupDownloadStateBinding()
    onLoad()
  }

  init(_ item: RecentlyPlayedItem) {
    self.item = item

    super.init(
      id: item.bookID,
      title: item.title,
      author: item.author,
      coverURL: item.coverURL,
      speed: SpeedPickerSheet.Model(),
      timer: TimerPickerSheet.Model(),
      playbackProgress: PlaybackProgressViewModel()
    )

    if let progress = userProgressService.progressByBookID[item.bookID],
      progress.currentTime > item.currentTime
    {
      self.currentTime = progress.currentTime
    } else {
      self.currentTime = item.currentTime
    }

    setupDownloadStateBinding()
    onLoad()
  }

  override func onTogglePlaybackTapped() {
    guard let player = player else { return }

    if isPlaying {
      player.pause()
    } else {
      player.play()
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
      downloadManager.startDownload(for: item)
    }
  }
}

extension BookPlayerModel {
  private func setupSessionInfo() async throws -> PlaySessionInfo {
    var sessionInfo: PlaySessionInfo?

    let hasExistingLocalSession = item?.playSessionInfo.isDownloaded == true

    do {
      print("Attempting to fetch fresh session from server...")

      let audiobookshelfSession: PlaySession
      if hasExistingLocalSession {
        audiobookshelfSession = try await audiobookshelf.sessions.start(
          itemID: id,
          forceTranscode: false
        )
      } else {
        audiobookshelfSession = try await audiobookshelf.sessions.start(
          itemID: id,
          forceTranscode: false
        )
      }

      let newPlaySessionInfo = PlaySessionInfo(from: audiobookshelfSession)

      if let serverCurrentTime = audiobookshelfSession.currentTime {
        currentTime = serverCurrentTime
        print("Using server currentTime for cross-device sync: \(serverCurrentTime)s")
      }

      if let item {
        item.playSessionInfo.merge(with: newPlaySessionInfo)
        item.currentTime = currentTime
        sessionInfo = item.playSessionInfo
        print("Merged fresh session with existing session to preserve local files")
      } else {
        let newItem = createRecentlyPlayedItem(for: newPlaySessionInfo)
        item = newItem
        sessionInfo = newPlaySessionInfo
      }

      print("Successfully fetched fresh session from server")

    } catch {
      print("Failed to fetch fresh session: \(error)")

      if let existingItem = item {
        let cachedSessionInfo = existingItem.playSessionInfo

        if cachedSessionInfo.isDownloaded {
          print("Using existing session with local files for offline playback")
          sessionInfo = cachedSessionInfo
          let cachedCurrentTime = existingItem.currentTime
          if cachedCurrentTime > 0 {
            currentTime = cachedCurrentTime
            print("Using existing currentTime: \(cachedCurrentTime)s")
          }
        } else {
          print("No local files available for offline playback")
          throw Audiobookshelf.AudiobookshelfError.networkError(
            "Cannot play without network connection or downloaded files")
        }
      } else {
        throw Audiobookshelf.AudiobookshelfError.networkError(
          "No cached session available for offline playback")
      }
    }

    guard let sessionInfo = sessionInfo else {
      throw Audiobookshelf.AudiobookshelfError.networkError("Failed to obtain session info")
    }

    return sessionInfo
  }

  private func setupAudioPlayer(sessionInfo: PlaySessionInfo) async throws -> AVPlayer {
    let playerItem: AVPlayerItem

    if let tracks = sessionInfo.orderedTracks, tracks.count > 1 {
      playerItem = try await createCompositionPlayerItem(from: tracks)
      print("Created composition with \(tracks.count) tracks")
    } else {
      guard let serverURL = audiobookshelf.authentication.serverURL else {
        print("No server URL available")
        ToastManager.shared.show(error: "No server URL available")
        isLoading = false
        PlayerManager.shared.clearCurrent()
        throw Audiobookshelf.AudiobookshelfError.networkError("No server URL available")
      }

      guard let streamingURL = sessionInfo.streamingURL(at: 0, serverURL: serverURL) else {
        print("Failed to get streaming URL - sessionInfo.streamingURL returned nil")
        ToastManager.shared.show(error: "Failed to get streaming URL")
        isLoading = false
        PlayerManager.shared.clearCurrent()
        throw Audiobookshelf.AudiobookshelfError.networkError("Failed to get streaming URL")
      }

      playerItem = AVPlayerItem(url: streamingURL)
    }

    let player = AVPlayer(playerItem: playerItem)
    self.player = player

    return player
  }

  private func configurePlayerComponents(player: AVPlayer, sessionInfo: PlaySessionInfo) {
    configureAudioSession()
    setupRemoteCommandCenter()
    setupPlayerObservers()
    setupTimeObserver()
    setupDownloadNotification()

    speed = SpeedPickerSheetViewModel(player: player)
    let timerViewModel = TimerPickerSheetViewModel()
    timerViewModel.setPlayer(player)
    timer = timerViewModel

    if let sessionChapters = sessionInfo.orderedChapters {
      chapters = ChapterPickerSheetViewModel(chapters: sessionChapters, player: player)
      timer.maxRemainingChapters = sessionChapters.count - 1
      print("Loaded \(sessionChapters.count) chapters from play session info")
    } else {
      chapters = nil
      print("No chapters available in play session info")
    }

    if let playbackProgress = playbackProgress as? PlaybackProgressViewModel {
      playbackProgress.configure(
        player: player,
        chapters: chapters,
        totalDuration: displayDuration
      )
    }
  }

  private func seekToLastPosition(player: AVPlayer) {
    if let recentlyPlayed = item, recentlyPlayed.currentTime > 0 {
      let seekTime = CMTime(seconds: recentlyPlayed.currentTime, preferredTimescale: 1000)
      let currentTime = recentlyPlayed.currentTime
      player.seek(to: seekTime) { _ in
        print("Seeked to previously played position: \(currentTime)s")
      }
    }
  }

  private func handleLoadError(_ error: Error) {
    print("Failed to setup player: \(error)")
    ToastManager.shared.show(error: "Failed to setup audio player")
    isLoading = false
    PlayerManager.shared.clearCurrent()
  }

  private func checkForExistingRecentlyPlayedItem() {
    guard item == nil else { return }

    do {
      if let existingItem = try RecentlyPlayedItem.fetch(bookID: id) {
        self.item = existingItem
        self.currentTime = existingItem.currentTime
        print("Found existing progress: \(existingItem.currentTime)s")
      }
    } catch {
      print("Failed to fetch existing recently played item: \(error)")
      ToastManager.shared.show(error: "Failed to load playback progress")
    }
  }

  private func onLoad() {
    Task {
      isLoading = true

      checkForExistingRecentlyPlayedItem()
      loadCover()

      do {
        let sessionInfo = try await setupSessionInfo()
        calculateTotalBookDuration()
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
    downloadManager.$downloads
      .map { [weak self] downloads in
        guard let item = self?.item else { return .notDownloaded }

        if let managerState = downloads[item.bookID] {
          return managerState
        }

        return item.playSessionInfo.isDownloaded ? .downloaded : .notDownloaded
      }
      .sink { [weak self] downloadState in
        self?.downloadState = downloadState
      }
      .store(in: &cancellables)
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
      currentItem.publisher(for: \.duration)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] duration in
          if duration.isValid && !duration.isIndefinite {
            self?.totalDuration = CMTimeGetSeconds(duration)
          }
        }
        .store(in: &cancellables)

      currentItem.publisher(for: \.status)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] status in
          switch status {
          case .readyToPlay:
            self?.isLoading = false
            let duration = currentItem.duration
            if duration.isValid && !duration.isIndefinite {
              self?.totalDuration = CMTimeGetSeconds(duration)
            }
          case .failed:
            self?.isLoading = false
            let errorMessage = currentItem.error?.localizedDescription ?? "Unknown error"
            print("Player item failed: \(errorMessage)")
            ToastManager.shared.show(error: "Audio playback failed: \(errorMessage)")
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

      Task { @MainActor in
        if time.isValid && !time.isIndefinite {
          self.currentTime = CMTimeGetSeconds(time)

          if let model = self.chapters as? ChapterPickerSheetViewModel {
            let previous = model.currentIndex
            model.setCurrentTime(self.currentTime)
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
            playbackProgress.updateCurrentTime(self.currentTime)
          }

          self.timerSecondsCounter += 1

          if self.timerSecondsCounter % 20 == 0 {
            self.updateRecentlyPlayedProgress()
            self.syncSessionProgress()
          }

          self.updateNowPlayingInfo()
        }
      }
    }
  }

  private func calculateTotalBookDuration() {
    guard let tracks = item?.playSessionInfo.orderedTracks else {
      totalBookDuration = nil
      return
    }

    let total = tracks.reduce(0.0) { $0 + $1.duration }
    totalBookDuration = total
    print("Total book duration: \(total) seconds across \(tracks.count) tracks")
  }

  private func createCompositionPlayerItem(from tracks: [AudioTrackInfo])
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
      guard let serverURL = audiobookshelf.serverURL,
        let trackURL = item?.playSessionInfo.streamingURL(for: track.index, serverURL: serverURL)
      else {
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

  private func createRecentlyPlayedItem(for sessionInfo: PlaySessionInfo) -> RecentlyPlayedItem {
    return RecentlyPlayedItem(
      bookID: id,
      title: title,
      author: author,
      coverURL: coverURL,
      lastPlayedAt: item?.lastPlayedAt ?? Date(),
      currentTime: currentTime,
      timeListened: item?.timeListened ?? 0,
      duration: displayDuration,
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
      ToastManager.shared.show(error: "Failed to save playback progress")
    }
  }

  private func setupDownloadNotification() {
    NotificationCenter.default.addObserver(
      forName: Notification.Name("DownloadCompleted"),
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self = self,
        let completedBookID = notification.object as? String,
        completedBookID == self.id
      else { return }

      Task { @MainActor in
        self.refreshPlayerForLocalPlayback()
      }
    }
  }

  private func refreshPlayerForLocalPlayback() {
    guard let player = self.player,
      let sessionInfo = item?.playSessionInfo
    else {
      print("Cannot refresh player - missing player or session info")
      return
    }

    print("Refreshing player to use local files")

    let currentTime = player.currentTime()
    let wasPlaying = isPlaying

    player.pause()

    Task {
      do {
        let playerItem: AVPlayerItem

        if let tracks = sessionInfo.orderedTracks, tracks.count > 1 {
          playerItem = try await createCompositionPlayerItem(from: tracks)
          print("Recreated composition with local files for \(tracks.count) tracks")
        } else {
          guard let serverURL = audiobookshelf.authentication.serverURL,
            let streamingURL = sessionInfo.streamingURL(at: 0, serverURL: serverURL)
          else {
            print("Failed to get local streaming URL")
            ToastManager.shared.show(error: "Failed to get local streaming URL")
            return
          }
          playerItem = AVPlayerItem(url: streamingURL)
          print("Using local file URL: \(streamingURL)")
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
        ToastManager.shared.show(error: "Failed to switch to downloaded files")
      }
    }
  }

  private func handlePlaybackStateChange(_ isNowPlaying: Bool) {
    let now = Date()

    if isNowPlaying && !isPlaying {
      lastPlaybackTime = now
    } else if !isNowPlaying && isPlaying {
      if let lastTime = lastPlaybackTime {
        let timeListened = now.timeIntervalSince(lastTime)
        item?.timeListened += timeListened
      }
      lastPlaybackTime = nil
    }
  }

  private func syncSessionProgress() {
    guard let sessionInfo = item?.playSessionInfo else { return }

    Task {
      do {
        try await audiobookshelf.sessions.sync(
          sessionInfo.id,
          timeListened: item?.timeListened ?? 0,
          currentTime: currentTime
        )

        item?.timeListened = 0
      } catch {
        print("Failed to sync session progress: \(error)")
      }
    }
  }

  private func updateRecentlyPlayedProgress() {
    guard let item else { return }

    do {
      item.currentTime = currentTime
      item.lastPlayedAt = Date()
      try item.save()
    } catch {
      print("Failed to update recently played progress: \(error)")
      ToastManager.shared.show(error: "Failed to update playback progress")
    }
  }

}
