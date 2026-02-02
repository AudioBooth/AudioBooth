import Foundation
import Models

final class PlaybackHistorySheetViewModel: PlaybackHistorySheet.Model {
  private let itemID: String
  private let onSeek: (TimeInterval) -> Void

  init(itemID: String, title: String, onSeek: @escaping (TimeInterval) -> Void) {
    self.itemID = itemID
    self.onSeek = onSeek
    super.init(title: title)
  }

  override func onAppear() {
    loadHistory()
  }

  override func onEntryTapped(_ entry: PlaybackHistoryRow.Model) {
    onSeek(entry.position)
    isPresented = false
  }

  private func loadHistory() {
    do {
      let entries = try PlaybackHistory.fetch(itemID: itemID)
      sections = groupEntriesByDate(entries)
    } catch {
      sections = []
    }
  }

  private func groupEntriesByDate(
    _ entries: [PlaybackHistory]
  ) -> [PlaybackHistorySheet.Model
    .Section]
  {
    let calendar = Calendar.current
    let now = Date()

    var grouped: [String: [PlaybackHistoryRow.Model]] = [:]
    var dateOrder: [String] = []

    for entry in entries {
      let sectionTitle = sectionTitle(for: entry.timestamp, calendar: calendar, now: now)

      if grouped[sectionTitle] == nil {
        grouped[sectionTitle] = []
        dateOrder.append(sectionTitle)
      }

      grouped[sectionTitle]?.append(PlaybackHistoryRow.Model(from: entry))
    }

    return dateOrder.compactMap { title -> PlaybackHistorySheet.Model.Section? in
      guard let entries = grouped[title], !entries.isEmpty else { return nil }
      return .init(title: title, entries: entries)
    }
  }

  private func sectionTitle(for date: Date, calendar: Calendar, now: Date) -> String {
    if calendar.isDateInToday(date) {
      return String(localized: "Today")
    } else if calendar.isDateInYesterday(date) {
      return String(localized: "Yesterday")
    } else {
      let formatter = DateFormatter()
      formatter.dateStyle = .medium
      formatter.timeStyle = .none
      return formatter.string(from: date)
    }
  }
}
