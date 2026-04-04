import SwiftUI

final class PlayerQueueViewModel: PlayerQueueView.Model {
  private let playerManager = PlayerManager.shared

  init() {
    let current = PlayerManager.shared.current
    let currentItem: QueueItem? = {
      guard let current else { return nil }

      return QueueItem(
        bookID: current.id,
        title: current.title,
        details: current.playbackProgress.totalTimeRemaining.formattedTimeRemaining,
        coverURL: current.coverURL,
        podcastID: current.podcastID
      )
    }()

    super.init(
      currentItem: currentItem,
      queue: PlayerManager.shared.queue
    )
  }

  override func onDelete(at offsets: IndexSet) {
    for index in offsets {
      let item = queue[index]
      playerManager.removeFromQueue(bookID: item.bookID)
    }
    queue.remove(atOffsets: offsets)
  }

  override func onMove(from source: IndexSet, to destination: Int) {
    queue.move(fromOffsets: source, toOffset: destination)
    playerManager.reorderQueue(queue)
  }

  override func onPlayTapped(_ item: QueueItem) {
    playerManager.playFromQueue(item)
    currentItem = item
    queue = playerManager.queue
  }

  override func onClearQueueTapped() {
    playerManager.clearQueue()
    queue = []
  }

  override func onClearCurrentTapped() {
    playerManager.clearCurrent()

    if UserPreferences.shared.autoPlayNextInQueue, let nextItem = queue.first {
      playerManager.playFromQueue(nextItem)
      currentItem = nextItem
      queue = playerManager.queue
    } else {
      currentItem = nil
    }
  }
}
