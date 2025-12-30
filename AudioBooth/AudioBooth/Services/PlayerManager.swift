import API
import Combine
import Logging
import MediaPlayer
import Models
import PlayerIntents
import SwiftUI
import WidgetKit

final class PlayerManager: ObservableObject, Sendable {
  private let userPreferences = UserPreferences.shared
  private let watchConnectivity = WatchConnectivityManager.shared

  static let shared = PlayerManager()

  @Published var current: BookPlayer.Model?
  @Published var isShowingFullPlayer = false
  @Published var reader: EbookReaderView.Model?

  private static let currentBookIDKey = "currentBookID"
  private let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")

  private var cancellables = Set<AnyCancellable>()

  private init() {
    setupRemoteCommandCenter()
  }

  func restoreLastPlayer() async {
    guard
      current == nil,
      ModelContextProvider.shared.activeServerID != nil,
      let savedBookID = UserDefaults.standard.string(forKey: Self.currentBookIDKey),
      let book = try? LocalBook.fetch(bookID: savedBookID)
    else {
      return
    }

    setCurrent(book)
  }

  var hasActivePlayer: Bool {
    current != nil
  }

  var isPlaying: Bool {
    current?.isPlaying ?? false
  }

  func setCurrent(_ book: LocalBook) {
    if book.bookID == current?.id {
      isShowingFullPlayer = true
    } else {
      if let currentPlayer = current as? BookPlayerModel {
        currentPlayer.stopPlayer()
      }
      current = BookPlayerModel(book)
      UserDefaults.standard.set(book.bookID, forKey: Self.currentBookIDKey)
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  func setCurrent(_ book: Book) {
    if book.id == current?.id {
      isShowingFullPlayer = true
    } else {
      if let currentPlayer = current as? BookPlayerModel {
        currentPlayer.stopPlayer()
      }
      current = BookPlayerModel(book)
      UserDefaults.standard.set(book.id, forKey: Self.currentBookIDKey)
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  func clearCurrent() {
    if let currentPlayer = current as? BookPlayerModel {
      currentPlayer.stopPlayer()
      currentPlayer.closeSession()
    }
    current = nil
    isShowingFullPlayer = false
    UserDefaults.standard.removeObject(forKey: Self.currentBookIDKey)
    sharedDefaults?.removeObject(forKey: "playbackState")
    watchConnectivity.clearPlaybackState()
    SessionManager.shared.clearSession()
    WidgetCenter.shared.reloadAllTimelines()
  }

  func showFullPlayer() {
    isShowingFullPlayer = true
  }

  func hideFullPlayer() {
    isShowingFullPlayer = false
  }

  func openLocalBookAsEbook(_ localBook: LocalBook) {
    if let ebookURL = localBook.ebookLocalPath {
      reader = EbookReaderViewModel(source: .local(ebookURL), bookID: localBook.bookID)
    } else {
      Toast(error: "Ebook file not available").show()
    }
  }

  func openRemoteBookAsEbook(_ book: Book) {
    if let ebookURL = book.ebookURL {
      reader = EbookReaderViewModel(source: .remote(ebookURL), bookID: book.id)
    } else {
      Toast(error: "Ebook not available").show()
    }
  }

  func closeEbookReader() {
    reader = nil
  }
}

extension PlayerManager: PlayerManagerProtocol {
  func play() {
    current?.onPlayTapped()
  }

  func pause() {
    current?.onPauseTapped()
  }

  func play(_ bookID: String) async {
    do {
      if current?.id == bookID {
        play()
      } else if let localBook = try LocalBook.fetch(bookID: bookID) {
        if !localBook.tracks.isEmpty {
          setCurrent(localBook)
          play()
        } else if localBook.ebookFile != nil {
          openLocalBookAsEbook(localBook)
        }
      } else {
        let book = try await Audiobookshelf.shared.books.fetch(id: bookID)
        if book.mediaType.contains(.audiobook) {
          setCurrent(book)
          play()
        } else if book.mediaType.contains(.ebook) {
          openRemoteBookAsEbook(book)
        }
      }
    } catch {
      print("Failed to play book: \(error)")
    }
  }

  func open(_ bookID: String) async {
    do {
      if current?.id == bookID {
        showFullPlayer()
      } else if let localBook = try LocalBook.fetch(bookID: bookID) {
        if localBook.ebookFile != nil {
          openLocalBookAsEbook(localBook)
        } else if !localBook.tracks.isEmpty {
          setCurrent(localBook)
          showFullPlayer()
        }
      } else {
        let book = try await Audiobookshelf.shared.books.fetch(id: bookID)
        if book.mediaType.contains(.ebook) {
          openRemoteBookAsEbook(book)
        } else if book.mediaType.contains(.audiobook) {
          setCurrent(book)
          showFullPlayer()
        }
      }
    } catch {
      print("Failed to open book: \(error)")
    }
  }
}

extension PlayerManager {
  private func observeSkipIntervalChanges() {
    userPreferences.objectWillChange
      .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        self?.updateRemoteCommand()
      }
      .store(in: &cancellables)
  }

  private func updateRemoteCommand() {
    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.skipForwardCommand.isEnabled = !userPreferences.lockScreenNextPreviousUsesChapters
    commandCenter.skipForwardCommand.preferredIntervals = [
      NSNumber(value: userPreferences.skipForwardInterval)
    ]

    commandCenter.skipBackwardCommand.isEnabled = !userPreferences.lockScreenNextPreviousUsesChapters
    commandCenter.skipBackwardCommand.preferredIntervals = [
      NSNumber(value: userPreferences.skipBackwardInterval)
    ]

    commandCenter.changePlaybackPositionCommand.isEnabled =
      userPreferences.lockScreenAllowPlaybackPositionChange
  }

  private func setupRemoteCommandCenter() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .spokenAudio)
      try audioSession.setActive(true)
    } catch {
      AppLogger.player.error("Failed to configure audio session: \(error)")
    }

    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      guard let current = self?.current else { return .commandFailed }

      current.onPlayTapped()

      return .success
    }

    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      guard let current = self?.current else { return .commandFailed }

      current.onPauseTapped()

      return .success
    }

    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let current = self?.current else { return .commandFailed }

      current.onTogglePlaybackTapped()

      return .success
    }

    commandCenter.stopCommand.isEnabled = true
    commandCenter.stopCommand.addTarget { [weak self] _ in
      guard let current = self?.current else { return .commandFailed }

      current.onPauseTapped()

      return .success
    }

    commandCenter.skipForwardCommand.isEnabled = !userPreferences.lockScreenNextPreviousUsesChapters
    commandCenter.skipForwardCommand.preferredIntervals = [
      NSNumber(value: userPreferences.skipForwardInterval)
    ]
    commandCenter.skipForwardCommand.addTarget { [weak self] event in
      guard let self, let current else { return .commandFailed }

      let interval: Double
      if let skipEvent = event as? MPSkipIntervalCommandEvent, skipEvent.interval > 0 {
        interval = skipEvent.interval
      } else {
        interval = userPreferences.skipForwardInterval
      }

      current.onSkipForwardTapped(seconds: interval)

      return .success
    }

    commandCenter.skipBackwardCommand.isEnabled = !userPreferences.lockScreenNextPreviousUsesChapters
    commandCenter.skipBackwardCommand.preferredIntervals = [
      NSNumber(value: userPreferences.skipBackwardInterval)
    ]
    commandCenter.skipBackwardCommand.addTarget { [weak self] event in
      guard let self, let current else { return .commandFailed }

      let interval: Double
      if let skipEvent = event as? MPSkipIntervalCommandEvent, skipEvent.interval > 0 {
        interval = skipEvent.interval
      } else {
        interval = userPreferences.skipBackwardInterval
      }

      current.onSkipBackwardTapped(seconds: interval)

      return .success
    }

    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      guard let self, let current else { return .commandFailed }

      if userPreferences.lockScreenNextPreviousUsesChapters, let chapters = current.chapters, !chapters.chapters.isEmpty
      {
        chapters.onNextChapterTapped()
      } else {
        current.onSkipForwardTapped(seconds: userPreferences.skipForwardInterval)
      }
      return .success
    }

    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      guard let self, let current else { return .commandFailed }

      if userPreferences.lockScreenNextPreviousUsesChapters, let chapters = current.chapters, !chapters.chapters.isEmpty
      {
        chapters.onPreviousChapterTapped()
      } else {
        current.onSkipBackwardTapped(seconds: userPreferences.skipBackwardInterval)
      }

      return .success
    }

    commandCenter.changePlaybackPositionCommand.isEnabled =
      userPreferences.lockScreenAllowPlaybackPositionChange
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let current = self?.current as? BookPlayerModel else { return .commandFailed }

      guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }

      let offset = current.chapters?.current?.start ?? 0
      current.seekToTime(offset + positionEvent.positionTime)

      return .success
    }

    commandCenter.changePlaybackRateCommand.isEnabled = true
    commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [0.7, 1.0, 1.2, 1.5, 1.7, 2.0].map {
      NSNumber(value: $0)
    }
    commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
      guard let current = self?.current else { return .commandFailed }

      guard let rateEvent = event as? MPChangePlaybackRateCommandEvent else {
        return .commandFailed
      }

      current.speed.onSpeedChanged(rateEvent.playbackRate)

      return .success
    }

    commandCenter.seekForwardCommand.isEnabled = true
    commandCenter.seekForwardCommand.addTarget { [weak self] _ in
      guard let self, let current else { return .commandFailed }

      current.onSkipForwardTapped(seconds: self.userPreferences.skipForwardInterval)

      return .success
    }

    commandCenter.seekBackwardCommand.isEnabled = true
    commandCenter.seekBackwardCommand.addTarget { [weak self] _ in
      guard let self, let current else { return .commandFailed }

      current.onSkipBackwardTapped(seconds: userPreferences.skipBackwardInterval)

      return .success
    }

    observeSkipIntervalChanges()
  }
}
