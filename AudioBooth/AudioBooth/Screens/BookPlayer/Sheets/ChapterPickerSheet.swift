import Combine
import SwiftUI

struct ChapterPickerSheet: View {
  @ObservedObject var model: Model

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        List {
          ForEach(Array(model.chapters.enumerated()), id: \.element.id) { index, chapter in
            Button(action: {
              model.onChapterTapped(at: index)
              model.isPresented = false
            }) {
              HStack {
                Text(chapter.title)
                  .font(.headline)
                  .fontWeight(model.currentIndex == index ? .bold : .regular)
                  .foregroundColor(.primary)
                  .lineLimit(2)

                Spacer()

                Text(formatDuration(chapter.end - chapter.start))
                  .font(.footnote)
                  .fontWeight(model.currentIndex == index ? .bold : .regular)
                  .foregroundColor(.primary)
              }
              .padding(.vertical, 4)
              .contentShape(Rectangle())
              .overlay(alignment: .leading) {
                if model.currentIndex == index {
                  RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 20)
                    .offset(x: -20)
                }
              }
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
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: model.onShuffleTapped) {
            Image(systemName: "shuffle")
          }
          .tint(model.isShuffled ? .accentColor : .primary)
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            model.isPresented = false
          }
          .tint(.primary)
        }
      }
    }
    .preferredColorScheme(.dark)
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    let hours = Int(duration) / 3600
    let minutes = Int(duration) % 3600 / 60
    let seconds = Int(duration) % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }
}

extension ChapterPickerSheet {
  @Observable
  class Model: ObservableObject {
    struct Chapter: Identifiable, Equatable {
      let id: Int
      let title: String
      let start: TimeInterval
      let end: TimeInterval
    }
    var chapters: [Chapter]
    var currentIndex: Int
    var isPresented: Bool = false
    var isShuffled: Bool = false

    init(chapters: [Chapter] = [], currentIndex: Int = 0) {
      self.chapters = chapters
      self.currentIndex = currentIndex
    }

    func onChapterTapped(at index: Int) {}
    func onPreviousChapterTapped() {}
    func onNextChapterTapped() {}
    func onShuffleTapped() {}
  }
}

extension ChapterPickerSheet.Model {
  var current: Chapter? {
    guard !chapters.isEmpty, currentIndex < chapters.count else { return nil }
    return chapters[currentIndex]
  }

  func currentProgress(currentTime: TimeInterval) -> Double {
    guard let current else { return 0.0 }

    let chapterDuration = current.end - current.start
    guard chapterDuration > 0 else { return 0.0 }

    let progressInChapter = currentTime - current.start
    return max(0.0, min(1.0, progressInChapter / chapterDuration))
  }

  func currentRemainingTime(currentTime: TimeInterval) -> TimeInterval {
    guard let current else { return 0.0 }
    return max(0.0, current.end - currentTime)
  }

  func currentElapsedTime(currentTime: TimeInterval) -> TimeInterval {
    guard let current else { return currentTime }
    return max(0.0, currentTime - current.start)
  }
}

extension ChapterPickerSheet.Model {
  static let mock = ChapterPickerSheet.Model(
    chapters: [
      Chapter(id: 1, title: "Chapter 1: The Beginning", start: 0, end: 1800),
      Chapter(id: 2, title: "Chapter 2: The Middle", start: 1800, end: 3600),
      Chapter(id: 3, title: "Chapter 3: The End", start: 3600, end: 5400),
    ],
    currentIndex: 0
  )
}

#Preview {
  ChapterPickerSheet(model: .mock)
}
