import AVFoundation
import Models
import SwiftUI

final class ChapterPickerSheetViewModel: ChapterPickerSheet.Model {
  let player: AVPlayer

  private var itemID: String

  private let mediaProgress: MediaProgress

  init(
    itemID: String,
    chapters: [Models.Chapter],
    mediaProgress: MediaProgress,
    player: AVPlayer
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

    let currentIndex = chapters.firstIndex(where: { chapter in
      chapter.start...chapter.end ~= mediaProgress.currentTime
    })

    super.init(
      chapters: convertedChapters,
      currentIndex: currentIndex ?? 0
    )

    observeMediaProgress()
  }

  private func observeMediaProgress() {
    withObservationTracking {
      _ = mediaProgress.currentTime
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        self.updateCurrentChapterFromTime()
        self.observeMediaProgress()
      }
    }
  }

  private func updateCurrentChapterFromTime() {
    for (index, chapter) in chapters.enumerated() {
      if chapter.start...chapter.end ~= mediaProgress.currentTime {
        if currentIndex != index {
          currentIndex = index
        }
        break
      }
    }
  }

  override func onPreviousChapterTapped() {
    let currentChapter = chapters[currentIndex]
    let timeInCurrentChapter = mediaProgress.currentTime - currentChapter.start

    if timeInCurrentChapter < 2.0 && currentIndex > 0 {
      let previousChapter = chapters[currentIndex - 1]
      currentIndex -= 1
      let seekTime = previousChapter.start + 0.1
      player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 1000))
      record(chapter: previousChapter, position: seekTime)
    } else {
      let chapter = chapters[currentIndex]
      let seekTime = currentChapter.start + 0.1
      player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 1000))
      record(chapter: chapter, position: seekTime)
    }
  }

  override func onNextChapterTapped() {
    guard currentIndex < chapters.count - 2 else { return }
    let nextChapter = chapters[currentIndex + 1]
    currentIndex += 1
    let seekTime = nextChapter.start + 0.1
    player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 1000))
    record(chapter: nextChapter, position: seekTime)
  }

  override func onChapterTapped(at index: Int) {
    let chapter = chapters[index]
    currentIndex = index
    let seekTime = chapter.start + 0.1
    player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 1000))
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
