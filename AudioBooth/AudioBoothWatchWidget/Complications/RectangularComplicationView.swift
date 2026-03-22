import SwiftUI
import WidgetKit

struct RectangularComplicationView: View {
  let entry: WatchComplicationEntry

  var body: some View {
    if let title = entry.bookTitle {
      bookView(title: title)
    } else {
      emptyStateView
    }
  }

  private func bookView(title: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2)

      if let timeRemaining = entry.timeRemaining {
        Text(formatTime(timeRemaining))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Gauge(value: entry.progress, in: 0...1) {
        EmptyView()
      }
      .gaugeStyle(.linearCapacity)
      .tint(.accentColor)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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

  private func formatTime(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " left"
  }
}
