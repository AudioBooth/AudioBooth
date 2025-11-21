import Foundation

final class ContinueListeningRowModel: ContinueListeningRow.Model {
  let book: WatchBook
  private let playerManager = PlayerManager.shared

  init(book: WatchBook) {
    self.book = book

    let timeRemainingText = Self.formatTimeRemaining(book.timeRemaining)

    super.init(
      id: book.id,
      title: book.title,
      author: book.authorName,
      coverURL: book.coverURL,
      timeRemaining: timeRemainingText
    )
  }

  private static func formatTimeRemaining(_ timeRemaining: Double) -> String? {
    guard timeRemaining > 0 else { return nil }
    return Duration.seconds(timeRemaining).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " left"
  }

  override func onTapped() {
    playerManager.setCurrent(book)
    playerManager.isShowingFullPlayer = true
  }
}
