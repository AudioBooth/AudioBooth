import Combine
import ReadiumShared
import SwiftUI

struct EbookChapterPickerSheet: View {
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
      .navigationTitle("Contents")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
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
