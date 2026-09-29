import SwiftUI
import WidgetKit

struct CircularComplicationView: View {
  let entry: WatchComplicationEntry

  private let ringWidth: CGFloat = 4
  private let ringSpacing: CGFloat = 1.5

  var body: some View {
    if entry.bookTitle != nil {
      bookView
    } else {
      emptyStateView
    }
  }

  private var bookView: some View {
    ZStack {
      AccessoryWidgetBackground()

      if let chapterInterval = entry.chapterInterval {
        dualRingTimerView(bookInterval: entry.bookInterval, chapterInterval: chapterInterval)
      } else if let chapterProgress = entry.chapterProgress {
        dualRingView(bookProgress: entry.progress, chapterProgress: chapterProgress)
      } else {
        singleRingView(progress: entry.progress)
      }
    }
  }

  private func dualRingTimerView(
    bookInterval: ClosedRange<Date>?,
    chapterInterval: ClosedRange<Date>
  ) -> some View {
    ZStack {
      timerRing(interval: chapterInterval)
        .padding(2)

      Group {
        if let bookInterval {
          timerRing(interval: bookInterval)
        } else {
          progressRing(progress: entry.progress)
        }
      }
      .padding(2 + ringWidth + ringSpacing)

      Image("audiobooth.fill")
        .font(.system(size: 18))
        .padding(.top, -2)
    }
  }

  private func timerRing(interval: ClosedRange<Date>) -> some View {
    ProgressView(timerInterval: interval, countsDown: false) {
      EmptyView()
    } currentValueLabel: {
      EmptyView()
    }
    .progressViewStyle(.circular)
    .tint(.orange)
    .widgetAccentable()
  }

  private func dualRingView(bookProgress: Double, chapterProgress: Double) -> some View {
    ZStack {
      progressRing(progress: chapterProgress)
        .padding(2)

      progressRing(progress: bookProgress)
        .padding(2 + ringWidth + ringSpacing)

      Image("audiobooth.fill")
        .font(.system(size: 18))
        .padding(.top, -2)
    }
  }

  private func singleRingView(progress: Double) -> some View {
    Gauge(value: progress, in: 0...1) {
      EmptyView()
    } currentValueLabel: {
      Image(systemName: "book.fill")
        .font(.caption)
    }
    .gaugeStyle(.accessoryCircular)
    .tint(.orange)
  }

  private func progressRing(progress: Double) -> some View {
    ZStack {
      Circle()
        .stroke(lineWidth: ringWidth)
        .opacity(0.2)

      Circle()
        .trim(from: 0, to: CGFloat(min(progress, 1.0)))
        .stroke(style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .foregroundStyle(.orange)
    .widgetAccentable()
  }

  private var emptyStateView: some View {
    ZStack {
      AccessoryWidgetBackground()
      Image(systemName: "book.fill")
        .font(.caption)
    }
  }
}
