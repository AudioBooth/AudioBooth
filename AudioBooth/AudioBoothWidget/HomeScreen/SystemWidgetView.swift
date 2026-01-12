import Models
import SwiftUI
import WidgetKit

struct SystemWidgetView: View {
  let entry: AudioBoothWidgetEntry
  @Environment(\.widgetFamily) var widgetFamily

  var body: some View {
    Group {
      switch widgetFamily {
      case .systemSmall:
        if let playbackState = entry.playbackState {
          SmallWidgetView(entry: entry, playbackState: playbackState)
            .widgetURL(URL(string: "audiobooth://open/\(playbackState.bookID)"))
        } else {
          emptyStateView
        }
      case .systemMedium:
        if let playbackState = entry.playbackState {
          MediumWidgetView(entry: entry, playbackState: playbackState)
            .widgetURL(URL(string: "audiobooth://open/\(playbackState.bookID)"))
        } else {
          emptyStateView
        }
      case .systemLarge:
        if !entry.recentBooks.isEmpty {
          LargeWidgetView(entry: entry, books: entry.recentBooks)
        } else {
          emptyStateView
        }
      default:
        if let playbackState = entry.playbackState {
          SmallWidgetView(entry: entry, playbackState: playbackState)
            .widgetURL(URL(string: "audiobooth://open/\(playbackState.bookID)"))
        } else {
          emptyStateView
        }
      }
    }
    .containerBackground(for: .widget) {
      LinearGradient(
        colors: [Color.black.opacity(0.8), Color.black.opacity(0.95)],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }

  private var emptyStateView: some View {
    VStack(spacing: 8) {
      Image(systemName: "book.circle")
        .font(.system(size: 30))
        .foregroundStyle(.primary.opacity(0.5))
      Text("Select a book to begin")
        .font(.caption2)
        .foregroundStyle(.primary.opacity(0.7))
    }
    .containerBackground(for: .widget) {
      Color.clear
    }
  }
}
