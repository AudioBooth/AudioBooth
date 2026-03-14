import ActivityKit
import PlayerIntents
import SwiftUI
import WidgetKit

struct SleepTimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: SleepTimerActivityAttributes.self) { context in
      LockScreenView(context: context)
    } dynamicIsland: { context in
      let accentColor = context.state.accentColor ?? Color.accentColor
      return DynamicIsland {
        DynamicIslandExpandedRegion(.center) {
          HStack {
            Image("audiobooth.fill")
              .foregroundStyle(accentColor)
            Text("Timer")
              .foregroundStyle(.secondary)
            TimerText(state: context.state)
              .font(.title2.bold())
              .foregroundStyle(accentColor)
          }
        }
      } compactLeading: {
        Image("audiobooth.fill")
          .foregroundStyle(accentColor)
      } compactTrailing: {
        TimerText(state: context.state)
          .font(.caption.bold())
          .foregroundStyle(accentColor)
      } minimal: {
        Image("audiobooth.fill")
          .foregroundStyle(accentColor)
      }
    }
  }
}

private struct TimerText: View {
  let state: SleepTimerActivityAttributes.ContentState

  var body: some View {
    HStack {
      switch state.timer {
      case .countdown(let endTime):
        TimelineView(.explicit([endTime])) { _ in
          if Date() >= endTime {
            Text(Duration.seconds(0), format: .time(pattern: .minuteSecond))
          } else {
            Text(endTime, style: .timer)
          }
        }
      case .paused(let remaining):
        Text(
          Duration.seconds(remaining),
          format: .time(pattern: remaining < 3600 ? .minuteSecond : .hourMinuteSecond)
        )
      }
    }
    .monospacedDigit()
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct LockScreenView: View {
  let context: ActivityViewContext<SleepTimerActivityAttributes>

  private var accentColor: Color {
    context.state.accentColor ?? Color.accentColor
  }

  var body: some View {
    HStack {
      Image("audiobooth.fill")
        .font(.title2)
        .foregroundStyle(accentColor)

      Text("Timer")
        .foregroundStyle(.secondary)

      TimerText(state: context.state)
        .font(.title.bold())
        .foregroundStyle(accentColor)
    }
    .padding()
  }
}
