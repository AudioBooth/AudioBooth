import SwiftUI
import WidgetKit

@main
struct AudioBoothWatchWidget: Widget {
  let kind: String = "AudioBoothWatchComplication"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
      WatchComplicationView(entry: entry)
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
