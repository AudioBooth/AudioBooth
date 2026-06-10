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
    guard let state = WatchComplicationStorage.load() else {
      completion(Timeline(entries: [.empty], policy: .never))
      return
    }

    guard state.isPlaying, let savedAt = state.savedAt else {
      completion(Timeline(entries: [currentEntry()], policy: .never))
      return
    }

    let now = Date()
    let rate = state.playbackRate ?? 1

    var entries: [WatchComplicationEntry] = []
    for minute in 0...60 {
      let entryDate = now.addingTimeInterval(Double(minute) * 60)
      let projectedTime = state.currentTime + entryDate.timeIntervalSince(savedAt) * rate

      entries.append(entry(for: state, currentTime: min(projectedTime, state.duration), date: entryDate))

      if projectedTime >= state.duration {
        break
      }
    }

    completion(Timeline(entries: entries, policy: .atEnd))
  }

  private func currentEntry() -> WatchComplicationEntry {
    guard let state = WatchComplicationStorage.load() else {
      return .empty
    }

    return entry(for: state, currentTime: state.currentTime, date: Date())
  }

  private func entry(
    for state: WatchComplicationState,
    currentTime: Double,
    date: Date
  ) -> WatchComplicationEntry {
    let chapterProgress: Double?
    if let start = state.chapterStart, let end = state.chapterEnd, end > start {
      chapterProgress = min(1, max(0, (currentTime - start) / (end - start)))
    } else {
      chapterProgress = state.chapterProgress
    }

    return WatchComplicationEntry(
      date: date,
      bookTitle: state.bookTitle,
      progress: state.duration > 0 ? min(1, currentTime / state.duration) : 0,
      chapterProgress: chapterProgress,
      timeRemaining: max(0, state.duration - currentTime),
      isPlaying: state.isPlaying
    )
  }
}
