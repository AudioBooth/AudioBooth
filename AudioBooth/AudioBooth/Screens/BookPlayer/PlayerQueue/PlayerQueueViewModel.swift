import SwiftUI

final class PlayerQueueViewModel: PlayerQueueView.Model {
  private let playerManager = PlayerManager.shared
  private let userPreferences = UserPreferences.shared
  private let dismiss: () -> Void

  init(dismiss: @escaping () -> Void) {
    self.dismiss = dismiss

    let current = PlayerManager.shared.current
    let currentItem: QueueItem? = {
      guard let current else { return nil }

      let details =
        Duration.seconds(current.playbackProgress.totalTimeRemaining).formatted(
          .units(
            allowed: [.hours, .minutes],
            width: .narrow
          )
        ) + " remaining"

      return QueueItem(
        bookID: current.id,
        title: current.title,
        details: details,
        coverURL: current.coverURL,
        podcastID: current.podcastID
      )
    }()

    super.init(
      currentItem: currentItem,
      queue: PlayerManager.shared.queue,
      autoPlayNext: UserPreferences.shared.autoPlayNextInQueue
    )

    observeAutoPlayNext()
  }

  override func onDoneTapped() {
    dismiss()
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

  override func onNowPlayingTapped() {
    dismiss()
    playerManager.showFullPlayer()
  }

  override func onClearQueueTapped() {
    playerManager.clearQueue()
    queue = []
  }

  override func onClearCurrentTapped() {
    playerManager.clearCurrent()

    if autoPlayNext, let nextItem = queue.first {
      playerManager.playFromQueue(nextItem)
      currentItem = nextItem
      queue = playerManager.queue
    } else {
      currentItem = nil
    }
  }

  private func observeAutoPlayNext() {
    withObservationTracking {
      _ = self.autoPlayNext
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        self.userPreferences.autoPlayNextInQueue = self.autoPlayNext
        self.observeAutoPlayNext()
      }
    }
  }
}
