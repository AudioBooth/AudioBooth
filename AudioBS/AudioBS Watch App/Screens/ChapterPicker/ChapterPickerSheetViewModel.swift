import AVFoundation
import Foundation
import Models

final class ChapterPickerSheetViewModel: ChapterPickerSheet.Model {
  let player: AVPlayer

  init(chapters: [ChapterInfo], player: AVPlayer, currentIndex: Int = 0) {
    self.player = player

    let convertedChapters = chapters.map { chapterInfo in
      ChapterPickerSheet.Model.Chapter(
        id: chapterInfo.id,
        title: chapterInfo.title,
        start: chapterInfo.start,
        end: chapterInfo.end
      )
    }

    super.init(chapters: convertedChapters, currentIndex: currentIndex)
  }

  override func onChapterTapped(at index: Int) {
    let chapter = chapters[index]
    currentIndex = index
    player.seek(to: CMTime(seconds: chapter.start + 0.1, preferredTimescale: 1000))
  }
}
