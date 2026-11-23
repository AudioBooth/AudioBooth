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

  @Published var current: BookPlayer.Model? {
    didSet {
      if let current {
        UserDefaults.standard.set(current.id, forKey: Self.currentIDKey)
      } else {
        UserDefaults.standard.removeObject(forKey: Self.currentIDKey)
      }
    }
  }
  @Published var isShowingFullPlayer = false
  @Published var reader: EbookReaderView.Model?
  @Published var isReaderOpen = false

  @Published private(set) var queue: [QueueItem] = [] {
    didSet {
      saveQueue()
    }
  }

  private static let currentIDKey = "currentBookID"
  private static let queueKey = "playerQueue"
  private let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")

  private var cancellables = Set<AnyCancellable>()
  private var serverID: String?

  private init() {
    migrateLegacyCurrentID()
    loadQueue()
    setupRemoteCommandCenter()
    setupServerObserver()
  }

  private func migrateLegacyCurrentID() {
    guard
      let storage = Audiobookshelf.shared.authentication.server?.storage,
      let libraryID = Audiobookshelf.shared.libraries.current?.id,
      let map = storage.dictionary(forKey: Self.currentIDKey) as? [String: String]
    else { return }

    storage.removeObject(forKey: Self.currentIDKey)

    if UserDefaults.standard.string(forKey: Self.currentIDKey) == nil {
      UserDefaults.standard.set(map[libraryID], forKey: Self.currentIDKey)
    }
  }

  private func setupServerObserver() {
    serverID = Audiobookshelf.shared.libraries.current?.serverID

    Audiobookshelf.shared.libraries.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self else { return }

        let currentServerID = Audiobookshelf.shared.libraries.current?.serverID
        if serverID != currentServerID {
          serverID = currentServerID
          sharedDefaults?.removeObject(forKey: "recentBooks")
          sharedDefaults?.removeObject(forKey: "listeningStats")
          clearCurrent()
          clearQueue()
        }
      }
      .store(in: &cancellables)
  }

  func restoreLastPlayer() {
    guard
      current == nil,
      ModelContextProvider.shared.activeServerID != nil,
      let savedID = UserDefaults.standard.string(forKey: Self.currentIDKey)
    else {
      return
    }

    restore(savedID)
  }

  private func lastPlayedID(in libraryID: String) -> String? {
    let isPodcastLibrary =
      Audiobookshelf.shared.libraries.libraries.first { $0.id == libraryID }?.mediaType == .podcast

    let itemIDs: Set<String>
    if isPodcastLibrary {
      itemIDs = Set((try? LocalEpisode.fetchAll())?.map(\.episodeID) ?? [])
    } else {
      itemIDs = Set(
        (try? LocalBook.fetchAll())?
          .filter { $0.libraryID == libraryID && $0.mediaType.contains(.audiobook) }
          .map(\.bookID) ?? []
      )
    }

    if let currentID = current?.id, itemIDs.contains(currentID) {
      return currentID
    }

    return (try? MediaProgress.fetchAll())?
      .first { itemIDs.contains($0.bookID) && $0.progress < 1 }?
      .bookID
  }

  func resumeLastPlayed(in libraryID: String) async throws {
    guard ModelContextProvider.shared.activeServerID != nil else {
      throw ResumePlaybackError.couldNotStart
    }

    guard let itemID = lastPlayedID(in: libraryID) else {
      throw ResumePlaybackError.nothingPlayed
    }

    if Audiobookshelf.shared.libraries.current?.id != libraryID,
      let library = Audiobookshelf.shared.libraries.libraries.first(where: { $0.id == libraryID })
    {
      Audiobookshelf.shared.libraries.current = library
    }

    if current?.id != itemID {
      restore(itemID)
    }

    guard current?.id == itemID else {
      throw ResumePlaybackError.couldNotStart
    }

    play()
  }

  private func restore(_ itemID: String) {
    if let book = try? LocalBook.fetch(bookID: itemID) {
      setCurrent(book)
    } else if let episode = try? LocalEpisode.fetch(episodeID: itemID) {
      setCurrent(episode)
    }
  }

  var hasActivePlayer: Bool {
    current != nil
  }

  var isPlaying: Bool {
    current?.isPlaying ?? false
  }

  func setCurrent(_ book: LocalBook) {
    setCurrent(id: book.bookID, BookPlayerModel(book))
  }

  func setCurrent(_ book: Book) {
    setCurrent(id: book.id, BookPlayerModel(book))
  }

  func setCurrent(
    episode: PodcastEpisode,
    podcastID: String,
    podcastTitle: String,
    podcastAuthor: String?,
    coverURL: URL?
  ) {
    setCurrent(
      id: episode.id,
      BookPlayerModel(
        episode,
        podcastID: podcastID,
        podcastTitle: podcastTitle,
        podcastAuthor: podcastAuthor,
        coverURL: coverURL
      )
    )
  }

  func setCurrent(_ episode: LocalEpisode) {
    setCurrent(id: episode.episodeID, BookPlayerModel(episode))
  }

  private func setCurrent(id: String, _ player: @autoclosure () -> BookPlayerModel) {
    if id == current?.id {
      isShowingFullPlayer = true
    } else {
      if let currentPlayer = current as? BookPlayerModel {
        currentPlayer.stopPlayer()
      }
      removeFromQueue(bookID: id)
      current = player()
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
    sharedDefaults?.removeObject(forKey: "playbackState")
    watchConnectivity.sendPlaybackRate(nil)
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
      reader = EbookReaderViewModel(source: .local(url: ebookURL, bookID: localBook.bookID))
    } else {
      Toast(error: "Ebook file not available").show()
    }
  }

  func openRemoteBookAsEbook(_ book: Book) {
    if book.ebookURL != nil {
      reader = EbookReaderViewModel(source: .book(book))
    } else {
      Toast(error: "Ebook not available").show()
    }
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
    await start(bookID, autoPlay: true)
  }

  func open(_ bookID: String) async {
    await start(bookID, autoPlay: false)
  }

  func open(episodeID: String, podcastID: String) async {
    await start(episodeID: episodeID, podcastID: podcastID, autoPlay: false)
  }

  private func start(_ bookID: String, autoPlay: Bool) async {
    do {
      if current?.id != bookID {
        if let localBook = try LocalBook.fetch(bookID: bookID) {
          switch destination(for: localBook.mediaType, autoPlay: autoPlay) {
          case .player: setCurrent(localBook)
          case .reader: return openLocalBookAsEbook(localBook)
          case nil: return
          }
        } else {
          let book = try await Audiobookshelf.shared.books.fetch(id: bookID)
          switch destination(for: book.mediaType, autoPlay: autoPlay) {
          case .player: setCurrent(book)
          case .reader: return openRemoteBookAsEbook(book)
          case nil: return
          }
        }
      }

      if autoPlay {
        play()
      } else {
        showFullPlayer()
      }
    } catch {
      AppLogger.player.error("Failed to start book: \(error)")
    }
  }

  private enum Destination {
    case player
    case reader
  }

  private func destination(for mediaType: Book.MediaType, autoPlay: Bool) -> Destination? {
    let isAudiobook = mediaType.contains(.audiobook)
    let isEbook = mediaType.contains(.ebook)

    if autoPlay, isAudiobook { return .player }
    if isEbook { return .reader }
    return isAudiobook ? .player : nil
  }

  private func start(episodeID: String, podcastID: String, autoPlay: Bool) async {
    if current?.id != episodeID {
      if let localEpisode = try? LocalEpisode.fetch(episodeID: episodeID) {
        setCurrent(localEpisode)
      } else {
        do {
          let podcast = try await Audiobookshelf.shared.podcasts.fetch(id: podcastID)
          guard let episode = podcast.media.episodes?.first(where: { $0.id == episodeID }) else { return }
          setCurrent(
            episode: episode,
            podcastID: podcastID,
            podcastTitle: podcast.title,
            podcastAuthor: podcast.author,
            coverURL: podcast.coverURL()
          )
        } catch {
          AppLogger.player.error("Failed to start episode: \(error)")
          return
        }
      }
    }

    if autoPlay {
      play()
    } else {
      showFullPlayer()
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
    let audioSession = AVAudioSession.sharedInstance()
    let mix = AudioSession.configure()
    if !mix, audioSession.isCarPlayConnected || !audioSession.secondaryAudioShouldBeSilencedHint {
      Task { await AudioSession.activate() }
    }

    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      guard let self, let current else { return .commandFailed }

      current.onPlayTapped()

      return .success
    }

    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      guard let self, let current else { return .commandFailed }

      if current.timer.extendIfNeeded() { return .success }

      current.onPauseTapped()

      return .success
    }

    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let self, let current else { return .commandFailed }

      if current.timer.extendIfNeeded() { return .success }

      current.onTogglePlaybackTapped()

      return .success
    }

    commandCenter.stopCommand.isEnabled = true
    commandCenter.stopCommand.addTarget { [weak self] _ in
      guard let self, let current else { return .commandFailed }

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
      guard let self, let current = current as? BookPlayerModel else { return .commandFailed }

      guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }

      if userPreferences.showFullBookDuration {
        current.seekToTime(positionEvent.positionTime)
      } else {
        let offset = current.chapters?.current?.start ?? 0
        current.seekToTime(offset + positionEvent.positionTime)
      }

      return .success
    }

    commandCenter.changePlaybackRateCommand.isEnabled = true
    commandCenter.changePlaybackRateCommand.supportedPlaybackRates = [0.7, 1.0, 1.2, 1.5, 1.7, 2.0].map {
      NSNumber(value: $0)
    }
    commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
      guard let self, let current else { return .commandFailed }

      guard let rateEvent = event as? MPChangePlaybackRateCommandEvent else {
        return .commandFailed
      }

      current.speed.onValueChanged(Double(rateEvent.playbackRate))

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

enum QueuePosition {
  case top
  case bottom
}

extension PlayerManager {
  func addToQueue(_ item: BookActionable) {
    guard item.bookID != current?.id else { return }
    guard !queue.contains(where: { $0.bookID == item.bookID }) else { return }
    queue.append(QueueItem(from: item))
  }

  func addToQueue(_ item: QueueItem, position: QueuePosition = .bottom) {
    guard item.bookID != current?.id else { return }
    guard !queue.contains(where: { $0.bookID == item.bookID }) else { return }
    switch position {
    case .top:
      queue.insert(item, at: 0)
    case .bottom:
      queue.append(item)
    }
  }

  func removeFromQueue(bookID: String) {
    queue.removeAll { $0.bookID == bookID }
  }

  func reorderQueue(_ newQueue: [QueueItem]) {
    queue = newQueue
  }

  func clearQueue() {
    queue.removeAll()
  }

  func playAll(_ items: [QueueItem]) {
    guard let first = items.first else { return }
    clearQueue()
    queue = Array(items.dropFirst())
    playItem(first, autoPlay: true)
  }

  func playNext(autoPlay: Bool = true, isManual: Bool = false) {
    if !queue.isEmpty, isManual || userPreferences.autoPlayNextInQueue {
      let nextItem = queue.removeFirst()
      playItem(nextItem, autoPlay: autoPlay)
      return
    }

    guard let currentID = current?.id else {
      clearCurrent()
      return
    }

    let currentPodcastID = current?.podcastID

    Task {
      let resolver = SmartContinueResolver()
      guard
        let resolved = await resolver.resolve(
          currentItemID: currentID,
          currentPodcastID: currentPodcastID
        )
      else {
        clearCurrent()
        return
      }

      let item = QueueItem(
        bookID: resolved.bookID,
        title: resolved.title,
        details: resolved.details,
        coverURL: resolved.coverURL,
        podcastID: resolved.podcastID
      )
      playItem(item, autoPlay: autoPlay)
    }
  }

  private func playItem(_ item: QueueItem, autoPlay: Bool) {
    restartIfFinished(item.bookID)

    Task {
      if let podcastID = item.podcastID {
        await start(episodeID: item.bookID, podcastID: podcastID, autoPlay: autoPlay)
      } else {
        await start(item.bookID, autoPlay: autoPlay)
      }
    }
  }

  func playFromQueue(_ item: QueueItem) {
    if let current, MediaProgress.progress(for: current.id) < 1 {
      let currentQueueItem = QueueItem(
        bookID: current.id,
        title: current.title,
        details: current.author,
        coverURL: current.coverURL,
        podcastID: current.podcastID
      )
      queue.insert(currentQueueItem, at: 0)
    }

    queue.removeAll { $0.bookID == item.bookID }
    playItem(item, autoPlay: true)
  }

  private func restartIfFinished(_ bookID: String) {
    if let mediaProgress = try? MediaProgress.fetch(bookID: bookID), mediaProgress.isFinished {
      mediaProgress.currentTime = 0
    }
  }

  fileprivate func saveQueue() {
    if let data = try? JSONEncoder().encode(queue) {
      UserDefaults.standard.set(data, forKey: Self.queueKey)
    }
  }

  fileprivate func loadQueue() {
    if let data = UserDefaults.standard.data(forKey: Self.queueKey),
      let savedQueue = try? JSONDecoder().decode([QueueItem].self, from: data)
    {
      queue = savedQueue
    }
  }

}
