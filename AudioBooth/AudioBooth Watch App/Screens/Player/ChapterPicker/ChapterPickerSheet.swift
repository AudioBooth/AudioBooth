import SwiftUI

struct ChapterPickerSheet: View {
  @Environment(\.dismiss) private var dismiss

  @Binding var model: Model

  var body: some View {
    ScrollViewReader { proxy in
      List {
        ForEach(Array(model.chapters.enumerated()), id: \.element.id) { index, chapter in
          Button(action: {
            model.onChapterTapped(at: index)
            dismiss()
          }) {
            VStack(alignment: .leading, spacing: 4) {
              Text(chapter.title)
                .font(.caption)
                .fontWeight(model.currentIndex == index ? .bold : .regular)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

              Text(formatDuration(chapter.end - chapter.start))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .overlay(alignment: .leading) {
              if model.currentIndex == index {
                RoundedRectangle(cornerRadius: 4)
                  .fill(Color.orange)
                  .frame(width: 4)
                  .padding(.vertical, 8)
                  .offset(x: -12)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .id(chapter.id)
        }
      }
      .onAppear {
        if let current = model.current {
          proxy.scrollTo(current.id, anchor: .center)
        }
      }
    }
    .navigationTitle("Chapters")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    let hours = Int(duration) / 3600
    let minutes = Int(duration) % 3600 / 60

    if hours > 0 {
      return "\(hours)h \(minutes)m"
    } else {
      return "\(minutes)m"
    }
  }
}

extension ChapterPickerSheet {
  @Observable class Model: Identifiable {
    let id = UUID()

    struct Chapter: Identifiable, Equatable {
      let id: Int
      let title: String
      let start: TimeInterval
      let end: TimeInterval
    }

    var chapters: [Chapter]
    var currentIndex: Int
    var isPresented: Bool = false

    init(chapters: [Chapter] = [], currentIndex: Int = 0) {
      self.chapters = chapters
      self.currentIndex = currentIndex
    }

    func onChapterTapped(at index: Int) {}
  }
}

extension ChapterPickerSheet.Model {
  var current: Chapter? {
    guard !chapters.isEmpty, currentIndex < chapters.count else { return nil }
    return chapters[currentIndex]
  }
}

#Preview {
  NavigationStack {
    ChapterPickerSheet(
      model: .constant(
        ChapterPickerSheet.Model(
          chapters: [
            .init(id: 1, title: "Chapter 1: The Beginning", start: 0, end: 1800),
            .init(id: 2, title: "Chapter 2: The Journey Continues", start: 1800, end: 3600),
            .init(id: 3, title: "Chapter 3: The Climax", start: 3600, end: 5400),
            .init(id: 4, title: "Chapter 4: Resolution", start: 5400, end: 7200),
          ],
          currentIndex: 1
        )
      )
    )
  }
}
