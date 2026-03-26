import Models
import SwiftUI

final class ChapterPickerSheetViewModel: ChapterPickerSheet.Model {
  let player: AudioPlayer

  private var itemID: String

  private let mediaProgress: MediaProgress
  private let playerManager = PlayerManager.shared
  private let userPreferences = UserPreferences.shared

  init(
    itemID: String,
    chapters: [Models.Chapter],
    mediaProgress: MediaProgress,
    player: AudioPlayer
  ) {
    self.itemID = itemID
    self.mediaProgress = mediaProgress
    self.player = player

    let convertedChapters = chapters.map { chapterInfo in
      ChapterPickerSheet.Model.Chapter(
        id: chapterInfo.id,
        title: chapterInfo.title,
        start: chapterInfo.start,
        end: chapterInfo.end
      )
    }

    let currentIndex = convertedChapters.index(for: mediaProgress.currentTime)

    super.init(
      chapters: convertedChapters,
      currentIndex: currentIndex
    )

    updateNavigation()
    observeMediaProgress()
  }

  private func observeMediaProgress() {
    withObservationTracking {
      _ = mediaProgress.currentTime
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        let time = self.mediaProgress.currentTime
        if self.isShuffled {
          self.currentIndex = self.chapters.unsortedIndex(for: time)
        } else {
          self.currentIndex = self.chapters.index(for: time)
        }
        self.updateNavigation()
        self.observeMediaProgress()
      }
    }
  }

  private func updateNavigation() {
    canGoPreviousChapter = currentIndex > 0
    let isLastChapter = currentIndex == chapters.count - 1
    canGoNextChapter = !isLastChapter || (!playerManager.queue.isEmpty && userPreferences.autoPlayNextInQueue)
  }

  override func onShuffleTapped() {
    isShuffled.toggle()
    if isShuffled {
      let current = chapters[currentIndex]
      var remaining = chapters
      remaining.remove(at: currentIndex)
      remaining.shuffle()
      chapters = [current] + remaining
      currentIndex = 0
    } else {
      let current = chapters[currentIndex]
      chapters.sort { $0.start < $1.start }
      currentIndex = chapters.firstIndex(of: current) ?? 0
    }
    updateNavigation()
  }

  override func onPreviousChapterTapped() {
    let currentChapter = chapters[currentIndex]
    let timeInCurrentChapter = mediaProgress.currentTime - currentChapter.start

    if timeInCurrentChapter < 2.0 && currentIndex > 0 {
      let previousChapter = chapters[currentIndex - 1]
      currentIndex -= 1
      let seekTime = previousChapter.start + 0.1
      player.seek(to: seekTime)
      record(chapter: previousChapter, position: seekTime)
    } else {
      let seekTime = currentChapter.start + 0.1
      player.seek(to: seekTime)
      record(chapter: currentChapter, position: seekTime)
    }
  }

  override func onNextChapterTapped() {
    guard currentIndex < chapters.count - 1 else {
      mediaProgress.currentTime = mediaProgress.duration
      player.pause()
      playerManager.playNext()
      return
    }
    currentIndex += 1
    let nextChapter = chapters[currentIndex]
    let seekTime = nextChapter.start + 0.1
    player.seek(to: seekTime)
    record(chapter: nextChapter, position: seekTime)
  }

  override func onChapterTapped(at index: Int) {
    let chapter = chapters[index]
    currentIndex = index
    let seekTime = chapter.start + 0.1
    player.seek(to: seekTime)
    record(chapter: chapter, position: seekTime)
  }

  private func record(chapter: Chapter, position: TimeInterval) {
    PlaybackHistory.record(
      itemID: itemID,
      action: .chapter,
      title: chapter.title,
      position: position
    )
  }
}

extension Array where Element == ChapterPickerSheet.Model.Chapter {
  func index(for time: TimeInterval) -> Int {
    var end: TimeInterval = .infinity
    for (index, chapter) in enumerated().reversed() {
      if chapter.start..<end ~= time {
        return index
      }
      end = chapter.start
    }
    return 0
  }

  func unsortedIndex(for time: TimeInterval) -> Int {
    for (index, chapter) in enumerated() {
      if time >= chapter.start && time < chapter.end {
        return index
      }
    }
    return 0
  }
}
