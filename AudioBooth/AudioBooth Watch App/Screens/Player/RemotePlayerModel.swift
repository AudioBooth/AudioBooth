import Combine
import Foundation

final class RemotePlayerModel: PlayerView.Model {
  private var cancellables = Set<AnyCancellable>()
  private let connectivityManager = WatchConnectivityManager.shared
  private var pendingState: Bool?

  init() {
    super.init(isReadyToPlay: true, isLocal: false)
    options = PlayerOptionsSheet.Model(isHidden: true, downloadState: .downloaded)
    setupBindings()
    updateFromCurrentBook()
  }

  private func setupBindings() {
    connectivityManager.$isPlaying
      .sink { [weak self] isPlaying in
        guard let self else { return }

        if let pending = self.pendingState, pending == isPlaying {
          self.pendingState = nil
        }

        if self.pendingState == nil {
          self.isPlaying = isPlaying
        }
      }
      .store(in: &cancellables)

    connectivityManager.$currentBook
      .sink { [weak self] _ in
        self?.updateFromCurrentBook()
      }
      .store(in: &cancellables)

    connectivityManager.$progress
      .sink { [weak self] _ in
        self?.updateFromCurrentBook()
      }
      .store(in: &cancellables)
  }

  private func updateFromCurrentBook() {
    guard let book = connectivityManager.currentBook else { return }

    let currentTime = connectivityManager.progress[book.id] ?? book.currentTime

    self.title = book.title
    self.author = book.authorName
    self.coverURL = book.coverURL
    self.current = currentTime
    self.remaining = max(0, book.duration - currentTime)
    self.totalTimeRemaining = self.remaining
    self.progress = book.duration > 0 ? currentTime / book.duration : 0

    updateCurrentChapter(currentTime: currentTime, chapters: book.chapters)
  }

  private func updateCurrentChapter(currentTime: Double, chapters: [WatchChapter]) {
    guard !chapters.isEmpty else {
      chapterTitle = nil
      return
    }

    for chapter in chapters {
      if currentTime >= chapter.start && currentTime < chapter.end {
        chapterTitle = chapter.title
        chapterCurrent = currentTime - chapter.start
        chapterRemaining = chapter.end - currentTime
        chapterProgress =
          chapter.duration > 0 ? (currentTime - chapter.start) / chapter.duration : 0
        return
      }
    }

    chapterTitle = nil
  }

  override func togglePlayback() {
    if isPlaying {
      connectivityManager.pause()
      pendingState = false
    } else {
      connectivityManager.play()
      pendingState = true
    }
    isPlaying.toggle()
  }

  override func skipBackward() {
    connectivityManager.skipBackward()
  }

  override func skipForward() {
    connectivityManager.skipForward()
  }
}
