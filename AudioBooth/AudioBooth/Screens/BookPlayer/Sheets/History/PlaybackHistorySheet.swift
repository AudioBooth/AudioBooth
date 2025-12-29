import Combine
import Models
import SwiftUI

struct PlaybackHistorySheet: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var model: Model

  var body: some View {
    NavigationStack {
      Group {
        if model.sections.isEmpty {
          emptyStateView
        } else {
          listView
        }
      }
      .navigationTitle("History")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .tint(.primary)
        }
      }
      .onAppear {
        model.onAppear()
      }
    }
  }

  private var emptyStateView: some View {
    ContentUnavailableView(
      "No History",
      systemImage: "clock.arrow.circlepath",
      description: Text("Your playback history will appear here.")
    )
  }

  private var listView: some View {
    List {
      ForEach(model.sections) { section in
        Section(header: Text(section.title)) {
          ForEach(section.entries) { entry in
            Button(action: { model.onEntryTapped(entry) }) {
              HStack(spacing: 12) {
                Text(
                  entry.timestamp.formatted(
                    .dateTime.hour(.twoDigits(amPM: .abbreviated)).minute(.twoDigits)
                  )
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

                PlaybackHistoryRow(model: entry)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }
}

extension PlaybackHistorySheet {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()
    var isPresented: Bool
    var sections: [Section]
    var title: String

    func onAppear() {}
    func onEntryTapped(_ entry: PlaybackHistoryRow.Model) {}

    init(
      isPresented: Bool = false,
      sections: [Section] = [],
      title: String = ""
    ) {
      self.isPresented = isPresented
      self.sections = sections
      self.title = title
    }
  }
}

extension PlaybackHistorySheet.Model {
  struct Section: Identifiable {
    let id = UUID()
    let title: String
    let entries: [PlaybackHistoryRow.Model]
  }
}

extension PlaybackHistorySheet.Model {
  static var mock: PlaybackHistorySheet.Model {
    let now = Date()
    let todayEntries: [PlaybackHistoryRow.Model] = [
      .init(actionType: .pause, position: 23448, timestamp: now.addingTimeInterval(-60)),
      .init(actionType: .seek, position: 23443, timestamp: now.addingTimeInterval(-65)),
      .init(actionType: .play, position: 12971, timestamp: now.addingTimeInterval(-3600)),
      .init(actionType: .seek, position: 23443, timestamp: now.addingTimeInterval(-3660)),
      .init(actionType: .seek, position: 18306, timestamp: now.addingTimeInterval(-3720)),
      .init(actionType: .pause, position: 8542, timestamp: now.addingTimeInterval(-7200)),
      .init(actionType: .play, position: 8530, timestamp: now.addingTimeInterval(-7260)),
    ]

    let yesterdayEntries: [PlaybackHistoryRow.Model] = [
      .init(actionType: .sync, position: 8530, timestamp: now.addingTimeInterval(-86400)),
      .init(actionType: .pause, position: 5200, timestamp: now.addingTimeInterval(-90000)),
      .init(actionType: .play, position: 3600, timestamp: now.addingTimeInterval(-93600)),
    ]

    return PlaybackHistorySheet.Model(
      sections: [
        .init(title: "Today", entries: todayEntries),
        .init(title: "Yesterday", entries: yesterdayEntries),
      ],
      title: "[Harry Potter 01] Philosopher's Stone"
    )
  }
}

#Preview {
  PlaybackHistorySheet(model: .mock)
}
