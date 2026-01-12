import SwiftUI
import WidgetKit

@main
struct AudioBoothWidgetBundle: WidgetBundle {
  var body: some Widget {
    AudioBoothWidget()
    AudioBoothLockscreenPlaybackWidget()
    AudioBoothLockscreenBookWidget()
  }
}

struct AudioBoothWidget: Widget {
  let kind: String = "AudioBoothWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: AudioBoothWidgetProvider()) { entry in
      SystemWidgetView(entry: entry)
    }
    .configurationDisplayName("Now Playing")
    .description("Shows your currently playing audiobook or recent books")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct AudioBoothLockscreenPlaybackWidget: Widget {
  let kind: String = "AudioBoothLockscreenCircular"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: AudioBoothWidgetProvider()) { entry in
      LockscreenPlaybackWidgetView(entry: entry)
    }
    .configurationDisplayName("Play/Pause")
    .description("Quick play/pause control with progress")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular])
  }
}

struct AudioBoothLockscreenBookWidget: Widget {
  let kind: String = "AudioBoothLockscreenBook"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: AudioBoothWidgetProvider()) { entry in
      LockscreenBookWidgetView(entry: entry)
    }
    .configurationDisplayName("AudioBooth")
    .description("Open now playing or recent book")
    .supportedFamilies([.accessoryCircular, .accessoryRectangular])
  }
}

struct LockscreenPlaybackWidgetView: View {
  let entry: AudioBoothWidgetEntry
  @Environment(\.widgetFamily) var widgetFamily

  var body: some View {
    switch widgetFamily {
    case .accessoryCircular:
      CircularPlaybackWidgetView(entry: entry)
    case .accessoryRectangular:
      RectangularBookWidgetView(entry: entry, action: .play)
    default:
      EmptyView()
    }
  }
}

struct LockscreenBookWidgetView: View {
  let entry: AudioBoothWidgetEntry
  @Environment(\.widgetFamily) var widgetFamily

  var body: some View {
    switch widgetFamily {
    case .accessoryCircular:
      CircularBookWidgetView(entry: entry)
    case .accessoryRectangular:
      RectangularBookWidgetView(entry: entry, action: .open)
    default:
      EmptyView()
    }
  }
}
