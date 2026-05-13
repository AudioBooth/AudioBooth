import Combine
import SwiftUI

struct ChaptersContent: View {
  @Environment(\.appTheme) var theme
  @ObservedObject var model: Model

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(model.chapters, id: \.id) { chapter in
        Button(action: { model.onChapterTapped(chapter) }) {
          HStack(spacing: 8) {
            Image(systemName: chapterIcon(for: chapter.status))
              .font(.caption)
              .foregroundColor(chapterColor(for: chapter.status))
              .frame(width: 16)

            Text(chapter.title)
              .font(.subheadline)
              .foregroundColor(chapterColor(for: chapter.status))
              .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatDuration(chapter.end - chapter.start))
              .font(.caption)
              .foregroundColor(.secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .padding(.vertical, 4)
      }
    }
    .padding()
    .background(theme.colors.background.card)
    .cornerRadius(8)
  }

  private func chapterIcon(for status: Chapter.Status) -> String {
    switch status {
    case .completed: "checkmark.circle.fill"
    case .current: "play.circle.fill"
    case .remaining: "circle"
    }
  }

  private func chapterColor(for status: Chapter.Status) -> Color {
    switch status {
    case .completed: .secondary
    case .current: .accentColor
    case .remaining: .primary
    }
  }

  private func formatDuration(_ seconds: Double) -> String {
    if seconds < 3600 {
      Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
    } else {
      Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 2)))
    }
  }
}

extension ChaptersContent {
  @Observable
  class Model: ObservableObject {
    var chapters: [Chapter]

    func onChapterTapped(_ chapter: Chapter) {}

    init(chapters: [Chapter]) {
      self.chapters = chapters
    }
  }

  struct Chapter {
    enum Status {
      case completed
      case current
      case remaining
    }

    let id: Int
    let start: TimeInterval
    let end: TimeInterval
    let title: String
    let status: Status
  }
}
