@preconcurrency import CarPlay
import Foundation

final class CarPlayChapters {
  private let interfaceController: CPInterfaceController
  private weak var currentPlayer: BookPlayer.Model?

  init(interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
  }

  func show(for player: BookPlayer.Model) {
    guard let chapters = player.chapters else { return }

    currentPlayer = player

    let currentIndex = chapters.currentIndex
    let remainingChapters = chapters.chapters.enumerated().filter { index, _ in
      index >= currentIndex
    }

    let items = remainingChapters.map { index, chapter in
      createListItem(for: chapter, at: index, isCurrent: index == currentIndex)
    }

    let section = CPListSection(items: items)
    let template = CPListTemplate(title: "Chapters", sections: [section])

    interfaceController.pushTemplate(template, animated: true, completion: nil)
  }

  private func createListItem(
    for chapter: ChapterPickerSheet.Model.Chapter,
    at index: Int,
    isCurrent: Bool
  ) -> CPListItem {
    let duration = formatDuration(chapter.end - chapter.start)

    let item = CPListItem(
      text: chapter.title,
      detailText: duration
    )

    item.handler = { [weak self] _, completion in
      self?.onChapterSelected(at: index)
      completion()
    }

    return item
  }

  private func onChapterSelected(at index: Int) {
    guard let player = currentPlayer,
      let chapters = player.chapters
    else { return }

    chapters.onChapterTapped(at: index)
    interfaceController.popTemplate(animated: true, completion: nil)
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    let hours = Int(duration) / 3600
    let minutes = Int(duration) % 3600 / 60
    let seconds = Int(duration) % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }
}
