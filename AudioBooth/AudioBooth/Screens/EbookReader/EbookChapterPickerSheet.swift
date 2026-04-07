import Combine
import ReadiumShared
import SwiftUI

struct EbookChapterPickerSheet: View {
  @ObservedObject var model: Model

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        List {
          ForEach(model.displayedChapters, id: \.chapter.id) { originalIndex, chapter in
            let isCurrent = model.displayedCurrentIndex == originalIndex
            Button(action: {
              model.onChapterTapped(at: originalIndex)
              model.isPresented = false
            }) {
              HStack {
                Text(chapter.title)
                  .font(chapter.level == 0 ? .headline : .subheadline)
                  .fontWeight(isCurrent ? .bold : .regular)
                  .foregroundColor(.primary)
                  .lineLimit(2)

                Spacer()
              }
              .padding(.leading, CGFloat(chapter.level) * 16)
              .padding(.vertical, 4)
              .contentShape(Rectangle())
              .overlay(alignment: .leading) {
                if isCurrent {
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
      .navigationTitle("Contents")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if model.hasSubchapters {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              model.showSubchapters.toggle()
            } label: {
              Image(systemName: model.showSubchapters ? "list.bullet.indent" : "list.bullet")
            }
            .tint(.primary)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close", systemImage: "xmark") {
            model.isPresented = false
          }
          .tint(.primary)
        }
      }
    }
  }
}

extension EbookChapterPickerSheet {
  @Observable
  class Model: ObservableObject {
    struct Chapter: Identifiable, Equatable {
      let id: String
      let title: String
      let link: ReadiumShared.Link
      var level: Int = 0
    }

    var chapters: [Chapter]
    var currentIndex: Int
    var isPresented: Bool = false
    var showSubchapters: Bool = false

    var hasSubchapters: Bool {
      chapters.contains(where: { $0.level > 0 })
    }

    var displayedCurrentIndex: Int {
      guard currentIndex < chapters.count else { return currentIndex }
      if chapters[currentIndex].level == 0 { return currentIndex }
      // Walk backwards to find the parent (level 0) chapter
      for i in stride(from: currentIndex - 1, through: 0, by: -1) {
        if chapters[i].level == 0 { return i }
      }
      return currentIndex
    }

    var displayedChapters: [(originalIndex: Int, chapter: Chapter)] {
      chapters.enumerated().compactMap { index, chapter in
        if showSubchapters || chapter.level == 0 {
          return (index, chapter)
        }
        return nil
      }
    }

    init(chapters: [Chapter] = [], currentIndex: Int = 0) {
      self.chapters = chapters
      self.currentIndex = currentIndex
    }

    func onChapterTapped(at index: Int) {}
  }
}

extension EbookChapterPickerSheet.Model {
  var current: Chapter? {
    guard !chapters.isEmpty, currentIndex < chapters.count else { return nil }
    return chapters[currentIndex]
  }
}

final class EbookChapterPickerViewModel: EbookChapterPickerSheet.Model {
  var onChapterSelected: ((Chapter) -> Void)?

  init(chapters: [Chapter]) {
    super.init(chapters: chapters, currentIndex: 0)
  }

  override func onChapterTapped(at index: Int) {
    guard index < chapters.count else { return }
    let chapter = chapters[index]
    onChapterSelected?(chapter)
  }
}
