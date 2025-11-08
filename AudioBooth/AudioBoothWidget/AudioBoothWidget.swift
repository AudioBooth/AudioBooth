import SwiftUI
import WidgetKit

@main
struct AudioBoothWidgetBundle: WidgetBundle {
  var body: some Widget {
    AudioBoothWidget()
  }
}

struct AudioBoothWidget: Widget {
  let kind: String = "AudioBoothWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: AudioBoothWidgetProvider()) { entry in
      AudioBoothWidgetView(entry: entry)
    }
    .configurationDisplayName("Now Playing")
    .description("Shows your currently playing audiobook")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
