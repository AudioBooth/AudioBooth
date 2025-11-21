import Foundation

final class BookChapterPickerModel: ChapterPickerSheet.Model {
  weak var playerModel: BookPlayerModel?

  init(chapters: [WatchChapter], playerModel: BookPlayerModel, currentIndex: Int) {
    self.playerModel = playerModel

    let chapterModels = chapters.map { chapter in
      ChapterPickerSheet.Model.Chapter(
        id: chapter.id,
        title: chapter.title,
        start: chapter.start,
        end: chapter.end
      )
    }

    super.init(chapters: chapterModels, currentIndex: currentIndex)
  }

  override func onChapterTapped(at index: Int) {
    playerModel?.seekToChapter(at: index)
    currentIndex = index
  }
}
