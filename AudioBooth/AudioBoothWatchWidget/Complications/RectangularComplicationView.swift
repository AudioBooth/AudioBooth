import SwiftUI
import UIKit
import WidgetKit

struct RectangularComplicationView: View {
  let entry: WatchComplicationEntry

  @Environment(\.widgetRenderingMode) private var renderingMode

  private let coverSize: CGFloat = 40

  var body: some View {
    if let title = entry.bookTitle {
      bookView(title: title)
    } else {
      emptyStateView
    }
  }

  private func bookView(title: String) -> some View {
    HStack(spacing: 6) {
      coverView

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.chapterTitle ?? title)
          .font(.caption2)
          .fontWeight(.semibold)
          .lineLimit(1)

        remainingView
          .font(.caption2)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .lineLimit(1)

        progressView
          .tint(.accentColor)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var coverView: some View {
    if let data = entry.coverData, let image = UIImage(data: data) {
      if #available(watchOS 11.0, *) {
        coverImage(Image(uiImage: image).resizable().widgetAccentedRenderingMode(.accentedDesaturated))
      } else if renderingMode == .fullColor {
        coverImage(Image(uiImage: image).resizable())
      } else {
        placeholderCover
      }
    } else {
      placeholderCover
    }
  }

  private func coverImage(_ image: some View) -> some View {
    image
      .aspectRatio(contentMode: .fill)
      .frame(width: coverSize, height: coverSize)
      .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private var placeholderCover: some View {
    Image(systemName: "book.fill")
      .font(.title3)
      .foregroundStyle(.secondary)
      .frame(width: coverSize, height: coverSize)
  }

  @ViewBuilder
  private var remainingView: some View {
    if let remaining = entry.chapterTimeRemaining ?? entry.timeRemaining {
      Text("\(formatTime(remaining)) left")
    }
  }

  @ViewBuilder
  private var progressView: some View {
    if let chapterInterval = entry.chapterInterval {
      timerProgressView(interval: chapterInterval)
    } else if let chapterProgress = entry.chapterProgress {
      ProgressView(value: min(max(chapterProgress, 0), 1))
    } else if let bookInterval = entry.bookInterval {
      timerProgressView(interval: bookInterval)
    } else {
      ProgressView(value: min(max(entry.progress, 0), 1))
    }
  }

  private func timerProgressView(interval: ClosedRange<Date>) -> some View {
    ProgressView(timerInterval: interval, countsDown: false) {
      EmptyView()
    } currentValueLabel: {
      EmptyView()
    }
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
    Duration.seconds((seconds / 60).rounded(.up) * 60).formatted(
      .units(allowed: [.hours, .minutes], width: .narrow)
    )
  }
}
