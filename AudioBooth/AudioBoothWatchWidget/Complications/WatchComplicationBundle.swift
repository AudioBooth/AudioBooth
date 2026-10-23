import SwiftUI
import WidgetKit

@main
struct AudioBoothWatchWidget: Widget {
  let kind: String = "AudioBoothWatchComplication"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
      WatchComplicationView(entry: entry)
        .containerBackground(.clear, for: .widget)
    }
    .configurationDisplayName("AudioBooth")
    .description("Shows your current audiobook progress")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner])
  }
}

struct WatchComplicationView: View {
  let entry: WatchComplicationEntry
  @Environment(\.widgetFamily) var widgetFamily

  var body: some View {
    switch widgetFamily {
    case .accessoryCircular:
      CircularComplicationView(entry: entry)
    case .accessoryRectangular:
      RectangularComplicationView(entry: entry)
    case .accessoryCorner:
      CornerComplicationView(entry: entry)
    default:
      EmptyView()
    }
  }
}

struct CornerComplicationView: View {
  let entry: WatchComplicationEntry

  var body: some View {
    Image(systemName: "book.fill")
      .font(.title3)
      .widgetLabel {
        if let title = entry.bookTitle {
          Gauge(value: entry.progress, in: 0...1) {
            Text(title)
          }
        } else {
          Text("AudioBooth")
        }
      }
  }
}

extension WatchComplicationEntry {
  @MainActor
  static var previewCover: Data? {
    let cover = LinearGradient(colors: [.orange, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
      .frame(width: 100, height: 100)
    return ImageRenderer(content: cover).uiImage?.jpegData(compressionQuality: 0.8)
  }

  @MainActor
  static var previewPlaying: WatchComplicationEntry {
    let now = Date()
    return WatchComplicationEntry(
      date: now,
      bookTitle: "Project Hail Mary",
      progress: 0.42,
      chapterProgress: 0.3,
      timeRemaining: 6 * 3600,
      bookInterval: now.addingTimeInterval(-4 * 3600)...now.addingTimeInterval(6 * 3600),
      chapterInterval: now.addingTimeInterval(-600)...now.addingTimeInterval(1400),
      chapterTitle: "Chapter 12: The Astrophage",
      chapterTimeRemaining: 1400,
      coverData: previewCover
    )
  }

  @MainActor
  static var previewPaused: WatchComplicationEntry {
    WatchComplicationEntry(
      date: Date(),
      bookTitle: "Project Hail Mary",
      progress: 0.42,
      chapterProgress: 0.3,
      timeRemaining: 6 * 3600,
      chapterTitle: "Chapter 12: The Astrophage",
      chapterTimeRemaining: 1400,
      coverData: previewCover
    )
  }

  static var previewNoChapters: WatchComplicationEntry {
    WatchComplicationEntry(
      date: Date(),
      bookTitle: "A Book Without Chapters",
      progress: 0.65,
      chapterProgress: nil,
      timeRemaining: 2 * 3600
    )
  }
}

#Preview("Rectangular", as: .accessoryRectangular) {
  AudioBoothWatchWidget()
} timeline: {
  WatchComplicationEntry.previewPlaying
  WatchComplicationEntry.previewPaused
  WatchComplicationEntry.previewNoChapters
  WatchComplicationEntry.empty
}

#Preview("Circular", as: .accessoryCircular) {
  AudioBoothWatchWidget()
} timeline: {
  WatchComplicationEntry.previewPlaying
  WatchComplicationEntry.previewPaused
  WatchComplicationEntry.previewNoChapters
  WatchComplicationEntry.empty
}

#Preview("Corner", as: .accessoryCorner) {
  AudioBoothWatchWidget()
} timeline: {
  WatchComplicationEntry.previewPaused
  WatchComplicationEntry.empty
}
