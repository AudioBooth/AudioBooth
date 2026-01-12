import AppIntents
import Models
import PlayerIntents
import SwiftUI
import WidgetKit

struct RectangularBookWidgetView: View {
  let entry: AudioBoothWidgetEntry

  enum Action {
    case play
    case open
  }
  let action: Action

  @AppStorage("timeRemainingAdjustsWithSpeed", store: UserDefaults(suiteName: "group.me.jgrenier.audioBS"))
  var timeRemainingAdjustsWithSpeed: Bool = true

  var body: some View {
    if let playbackState = entry.playbackState {
      playingBookView(playbackState: playbackState)
    } else if let recentBook = entry.recentBooks.first {
      recentBookView(recentBook: recentBook)
    } else {
      emptyStateView
    }
  }

  func intent(bookID: String) -> any AppIntent {
    switch action {
    case .play:
      PlayBookIntent(bookID: bookID)
    case .open:
      OpenBookIntent(bookID: bookID)
    }
  }

  private func playingBookView(playbackState: PlaybackState) -> some View {
    Button(intent: intent(bookID: playbackState.bookID)) {
      VStack(alignment: .leading, spacing: 2) {
        Text(playbackState.title)
          .font(.caption)
          .fontWeight(.medium)
          .lineLimit(2)

        HStack(spacing: 4) {
          Image(systemName: playbackState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
            .font(.caption2)

          Text(formatTime(calculateTimeRemaining(playbackState: playbackState)))
            .font(.caption2)
        }
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
  }

  private func recentBookView(recentBook: BookListEntry) -> some View {
    Button(intent: intent(bookID: recentBook.bookID)) {
      VStack(alignment: .leading, spacing: 2) {
        Text(recentBook.title)
          .font(.caption)
          .fontWeight(.medium)
          .lineLimit(2)

        Text(recentBook.author)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
  }

  private var emptyStateView: some View {
    VStack(spacing: 4) {
      Image(systemName: "book.fill")
        .font(.title3)
        .foregroundStyle(.secondary)

      Text("No Recent Books")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  private func calculateTimeRemaining(playbackState: PlaybackState) -> TimeInterval {
    var remaining = playbackState.duration - playbackState.currentTime
    if timeRemainingAdjustsWithSpeed {
      remaining /= Double(playbackState.playbackSpeed)
    }
    return remaining
  }

  private func formatTime(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " left"
  }
}
