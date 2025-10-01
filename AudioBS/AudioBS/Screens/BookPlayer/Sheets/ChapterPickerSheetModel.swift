import AVFoundation
import Models
import SwiftUI

final class ChapterPickerSheetViewModel: ChapterPickerSheet.Model {
  let player: AVPlayer

  private var currentTime: TimeInterval = 0
  private var onSeekToTime: ((TimeInterval) -> Void)?

  init(chapters: [ChapterInfo], player: AVPlayer) {
    self.player = player

    let convertedChapters = chapters.map { chapterInfo in
      ChapterPickerSheet.Model.Chapter(
        id: chapterInfo.id,
        title: chapterInfo.title,
        start: chapterInfo.start,
        end: chapterInfo.end
      )
    }

    super.init(chapters: convertedChapters, currentIndex: 0)
  }

  func setCurrentTime(_ time: TimeInterval) {
    currentTime = time
    updateCurrentChapterFromTime()
  }

  private func updateCurrentChapterFromTime() {
    for (index, chapter) in chapters.enumerated() {
      if currentTime >= chapter.start && currentTime < chapter.end {
        if currentIndex != index {
          currentIndex = index
        }
        break
      }
    }
  }

  func onPreviousChapterTapped() {
    guard currentIndex > 0 else { return }
    let previousChapter = chapters[currentIndex - 1]
    currentIndex -= 1
    player.seek(to: CMTime(seconds: previousChapter.start + 0.1, preferredTimescale: 1000))
  }

  func onNextChapterTapped() {
    guard currentIndex < chapters.count - 2 else { return }
    let nextChapter = chapters[currentIndex + 1]
    currentIndex += 1
    player.seek(to: CMTime(seconds: nextChapter.start + 0.1, preferredTimescale: 1000))
  }

  override func onChapterTapped(at index: Int) {
    let chapter = chapters[index]
    currentIndex = index
    player.seek(to: CMTime(seconds: chapter.start + 0.1, preferredTimescale: 1000))
  }
}
