import Foundation
import WidgetKit

struct WatchComplicationProvider: TimelineProvider {
  func placeholder(in context: Context) -> WatchComplicationEntry {
    WatchComplicationEntry(
      date: Date(),
      bookTitle: "Book Title",
      progress: 0.35,
      chapterProgress: 0.6,
      timeRemaining: 3600,
      isPlaying: false
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
    completion(currentEntry())
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<WatchComplicationEntry>) -> Void
  ) {
    let entry = currentEntry()
    let timeline = Timeline(entries: [entry], policy: .never)
    completion(timeline)
  }

  private func currentEntry() -> WatchComplicationEntry {
    guard let state = WatchComplicationStorage.load() else {
      return .empty
    }

    return WatchComplicationEntry(
      date: Date(),
      bookTitle: state.bookTitle,
      progress: state.progress,
      chapterProgress: state.chapterProgress,
      timeRemaining: state.timeRemaining,
      isPlaying: state.isPlaying
    )
  }
}
