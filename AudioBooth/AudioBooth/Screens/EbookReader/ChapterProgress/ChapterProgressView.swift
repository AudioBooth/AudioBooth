import Combine
import SwiftUI

struct ChapterProgressView: View {
  static let height: CGFloat = 56

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
          if !model.showsPages {
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
    .padding(.bottom, 16)
    .frame(height: Self.height)
    .frame(maxWidth: .infinity)
    .background(model.backgroundColor.ignoresSafeArea(edges: .top))
    .allowsHitTesting(false)
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
    var showsPages: Bool
    var page: Int
    var visiblePageCount: Int
    var pageCount: Int
    var chapterFraction: Double
    var bookFraction: Double
    var backgroundColor: Color

    init(
      chapterTitle: String? = nil,
      showsPages: Bool = true,
      page: Int = 0,
      visiblePageCount: Int = 1,
      pageCount: Int = 0,
      chapterFraction: Double = 0,
      bookFraction: Double = 0,
      backgroundColor: Color = .clear
    ) {
      self.chapterTitle = chapterTitle
      self.showsPages = showsPages
      self.page = page
      self.visiblePageCount = visiblePageCount
      self.pageCount = pageCount
      self.chapterFraction = chapterFraction
      self.bookFraction = bookFraction
      self.backgroundColor = backgroundColor
    }
  }
}
