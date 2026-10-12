import Combine
import SwiftUI

struct ChapterProgressView: View {
  static let height: CGFloat = 40
  static let pagedBottomPadding: CGFloat = 16

  @ObservedObject var model: Model

  var body: some View {
    VStack(spacing: 8) {
      Capsule()
        .fill(.quaternary)
        .overlay(alignment: .leading) {
          GeometryReader { proxy in
            Rectangle()
              .fill(Color.accentColor)
              .frame(width: proxy.size.width * min(max(model.chapterFraction, 0), 1))
          }
        }
        .clipShape(Capsule())
        .frame(height: 4)

      ZStack {
        HStack {
          if model.isScrollMode {
            Text(model.chapterFraction.formatted(.percent.precision(.fractionLength(0))))
          } else if model.pageCount > 0 {
            Text(verbatim: "\(pageLabel) / \(model.pageCount)")
          }
          Spacer()
          Text(model.bookFraction.formatted(.percent.precision(.fractionLength(1))))
        }
        .monospacedDigit()

        if let chapterTitle = model.chapterTitle {
          Text(chapterTitle)
            .lineLimit(1)
            .padding(.horizontal, 72)
        }
      }
      .font(.system(size: 12))
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 16)
    .frame(height: Self.height)
    .padding(.bottom, model.isScrollMode ? 0 : Self.pagedBottomPadding)
    .frame(maxWidth: .infinity)
  }

  private var pageLabel: String {
    let lastVisiblePage = min(model.page + model.visiblePageCount - 1, model.pageCount)
    return lastVisiblePage > model.page ? "\(model.page)-\(lastVisiblePage)" : "\(model.page)"
  }
}

extension ChapterProgressView {
  @Observable
  class Model: ObservableObject {
    var chapterTitle: String?
    var isScrollMode: Bool
    var page: Int
    var visiblePageCount: Int
    var pageCount: Int
    var chapterFraction: Double
    var bookFraction: Double

    init(
      chapterTitle: String? = nil,
      isScrollMode: Bool = false,
      page: Int = 0,
      visiblePageCount: Int = 1,
      pageCount: Int = 0,
      chapterFraction: Double = 0,
      bookFraction: Double = 0
    ) {
      self.chapterTitle = chapterTitle
      self.isScrollMode = isScrollMode
      self.page = page
      self.visiblePageCount = visiblePageCount
      self.pageCount = pageCount
      self.chapterFraction = chapterFraction
      self.bookFraction = bookFraction
    }
  }
}
