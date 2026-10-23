import Foundation
import WidgetKit

struct WatchComplicationProvider: TimelineProvider {
  private let maxTimelineEntries = 50

  func placeholder(in context: Context) -> WatchComplicationEntry {
    WatchComplicationEntry(
      date: Date(),
      bookTitle: "Book Title",
      progress: 0.35,
      chapterProgress: 0.6,
      timeRemaining: 3600
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
    let snapshot = WatchComplicationStorage.load().map { state in
      entry(for: state, at: Date(), coverData: coverData(for: state))
    }
    completion(snapshot ?? .empty)
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<WatchComplicationEntry>) -> Void
  ) {
    guard let state = WatchComplicationStorage.load() else {
      completion(Timeline(entries: [.empty], policy: .never))
      return
    }

    let cover = coverData(for: state)
    var entries = [entry(for: state, at: Date(), coverData: cover)]
    while entries.count < maxTimelineEntries, let date = entries.last.flatMap(nextChangeDate(after:)) {
      entries.append(entry(for: state, at: date, coverData: cover))
    }

    let policy: TimelineReloadPolicy = entries.last.flatMap(nextChangeDate(after:)).map { .after($0) } ?? .never

    completion(Timeline(entries: entries, policy: policy))
  }

  private func nextChangeDate(after entry: WatchComplicationEntry) -> Date? {
    let periodEnd = entry.chapterInterval.map { $0.upperBound.addingTimeInterval(1) } ?? entry.bookInterval?.upperBound
    let nextMinute = entry.bookInterval.map { _ in entry.date.addingTimeInterval(60) }
    return [periodEnd, entry.playbackExpiresAt, nextMinute].compactMap { $0 }.min()
  }

  private func coverData(for state: WatchComplicationState) -> Data? {
    guard let bookID = state.bookID, let url = WatchComplicationStorage.coverURL(for: bookID) else { return nil }
    return try? Data(contentsOf: url)
  }

  private func entry(for state: WatchComplicationState, at now: Date, coverData: Data?) -> WatchComplicationEntry {
    let rate = max(0.1, state.playbackRate ?? 1)

    var currentTime = state.currentTime
    var isPlaying = false
    if state.isPlaying, let savedAt = state.savedAt {
      let isExpired = state.playbackExpiresAt.map { $0 <= now } ?? false
      let playedUntil = min(now, state.playbackExpiresAt ?? now)
      currentTime += max(0, playedUntil.timeIntervalSince(savedAt)) * rate
      isPlaying = !isExpired && currentTime < state.duration
    }
    currentTime = min(currentTime, max(state.duration, 0))

    let chapter = chapterBounds(for: state, at: currentTime)
    let isInChapter = chapter.map { $0.lowerBound <= currentTime && currentTime < $0.upperBound } ?? false

    let chapterProgress: Double?
    if let chapter, chapter.upperBound > chapter.lowerBound {
      chapterProgress = min(1, max(0, (currentTime - chapter.lowerBound) / (chapter.upperBound - chapter.lowerBound)))
    } else {
      chapterProgress = state.chapterProgress
    }

    var bookInterval: ClosedRange<Date>?
    var chapterInterval: ClosedRange<Date>?

    if isPlaying {
      bookInterval =
        now.addingTimeInterval(-currentTime / rate)...now.addingTimeInterval((state.duration - currentTime) / rate)

      if let chapter, isInChapter {
        chapterInterval =
          now.addingTimeInterval(
            -(currentTime - chapter.lowerBound) / rate
          )...now.addingTimeInterval(
            (chapter.upperBound - currentTime) / rate
          )
      }
    }

    return WatchComplicationEntry(
      date: now,
      bookTitle: state.bookTitle,
      progress: state.duration > 0 ? min(1, currentTime / state.duration) : 0,
      chapterProgress: chapterProgress,
      timeRemaining: max(0, state.duration - currentTime) / rate,
      bookInterval: bookInterval,
      chapterInterval: chapterInterval,
      playbackExpiresAt: isPlaying ? state.playbackExpiresAt : nil,
      chapterTitle: chapterTitle(for: state, at: currentTime),
      chapterTimeRemaining: chapter.flatMap { isInChapter ? ($0.upperBound - currentTime) / rate : nil },
      coverData: coverData,
      relevance: TimelineEntryRelevance(score: isPlaying ? 100 : 0)
    )
  }

  private func chapterIndex(for state: WatchComplicationState, at time: Double) -> Int? {
    state.chapterStarts?.lastIndex(where: { $0 <= time })
  }

  private func chapterTitle(for state: WatchComplicationState, at time: Double) -> String? {
    guard let titles = state.chapterTitles, let index = chapterIndex(for: state, at: time),
      titles.indices.contains(index)
    else { return nil }
    return titles[index]
  }

  private func chapterBounds(for state: WatchComplicationState, at time: Double) -> ClosedRange<Double>? {
    if let starts = state.chapterStarts, let index = chapterIndex(for: state, at: time) {
      let end = index + 1 < starts.count ? starts[index + 1] : state.duration
      return end > starts[index] ? starts[index]...end : nil
    }

    if let start = state.chapterStart, let end = state.chapterEnd, end > start {
      return start...end
    }

    return nil
  }
}
