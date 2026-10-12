import Combine
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit
import WebKit

final class ChapterProgressViewModel: ChapterProgressView.Model {
  var chapters: EbookChapterPickerSheet.Model? {
    didSet { updateChapterTitle() }
  }

  private weak var navigator: EPUBNavigatorViewController?
  private let publication: Publication
  private let positions: [Locator]
  private let preferences: EbookReaderPreferences

  private weak var scrollView: UIScrollView?
  private var resourceIndex: Int?
  private var chapterPositions: [Locator] = []
  private var columnCount = 1

  private var spreadObservation: AnyCancellable?
  private var scrollObservation: AnyCancellable?
  private var layoutObservation: AnyCancellable?

  init(
    navigator: EPUBNavigatorViewController,
    publication: Publication,
    positions: [Locator],
    preferences: EbookReaderPreferences
  ) {
    self.navigator = navigator
    self.publication = publication
    self.positions = positions
    self.preferences = preferences

    super.init()
  }

  func onLocationChanged() {
    observeSpreadScroll()
    refresh()
  }

  private func observeSpreadScroll() {
    guard spreadObservation == nil, let navigator,
      let spreadScrollView = paginationScrollView(in: navigator.view)
    else {
      return
    }

    spreadObservation = spreadScrollView.publisher(for: \.contentOffset)
      .sink { [weak self, weak spreadScrollView] _ in
        guard let self, let spreadScrollView else { return }
        self.onSpreadScrolled(spreadScrollView)
      }
  }

  private func onSpreadScrolled(_ spreadScrollView: UIScrollView) {
    guard let navigator, spreadScrollView.bounds.width > 0 else { return }

    let isRTL = navigator.settings.readingProgression == .rtl
    let offset =
      isRTL
      ? spreadScrollView.contentSize.width - spreadScrollView.contentOffset.x - spreadScrollView.bounds.width
      : spreadScrollView.contentOffset.x
    let index = Int((offset / spreadScrollView.bounds.width).rounded())

    if index != resourceIndex, publication.readingOrder.indices.contains(index) {
      resourceIndex = index
      let href = publication.readingOrder[index].url().string
      chapterPositions = positions.filter { $0.href.string == href }
      updateChapterTitle()
    }

    updateScrollView(in: navigator.view)
    refresh()
  }

  private func updateChapterTitle() {
    guard let chapters, let resourceIndex else { return }

    let readingOrder = publication.readingOrder
    chapterTitle =
      chapters.chapters.last(where: { chapter in
        guard let chapterResourceIndex = readingOrder.firstIndexWithHREF(chapter.link.url()) else { return false }
        return chapterResourceIndex <= resourceIndex
      })?.title
  }

  private func updateScrollView(in view: UIView) {
    let center = view.window?.bounds.midX ?? 0
    let closestWebView = webViews(in: view).min { lhs, rhs in
      abs(lhs.convert(lhs.bounds, to: nil).midX - center) < abs(rhs.convert(rhs.bounds, to: nil).midX - center)
    }

    guard let scrollView = closestWebView?.scrollView, scrollView !== self.scrollView else { return }
    self.scrollView = scrollView

    scrollObservation = scrollView.publisher(for: \.contentOffset)
      .sink { [weak self] _ in
        self?.refresh()
      }

    layoutObservation = scrollView.publisher(for: \.contentSize)
      .sink { [weak self] _ in
        self?.updateColumnCount()
      }
  }

  private func updateColumnCount() {
    refresh()

    guard !preferences.scroll, let webView = scrollView?.superview as? WKWebView else {
      columnCount = 1
      return
    }

    Task { [weak self] in
      let value = try? await webView.evaluateJavaScript(
        "String(getComputedStyle(document.documentElement).columnCount)"
      )
      guard let self else { return }
      self.columnCount = max(Int(value as? String ?? "") ?? 1, 1)
      self.refresh()
    }
  }

  private func refresh() {
    let totalProgression = navigator?.currentLocation?.locations.totalProgression ?? bookFraction

    guard let scrollView, let screens = screenPages(in: scrollView) else {
      bookFraction = totalProgression
      return
    }

    isScrollMode = preferences.scroll
    page = screens.current
    visiblePageCount = preferences.scroll ? 1 : columnCount
    pageCount = screens.total
    chapterFraction = screens.fraction

    if let firstPosition = chapterPositions.first?.locations.position, !positions.isEmpty {
      let chapterStart = Double(firstPosition - 1)
      let chapterLength = Double(chapterPositions.count)
      bookFraction = (chapterStart + screens.fraction * chapterLength) / Double(positions.count)
    } else {
      bookFraction = totalProgression
    }
  }

  private func screenPages(in scrollView: UIScrollView) -> (current: Int, total: Int, fraction: Double)? {
    let insets = scrollView.adjustedContentInset
    let isVertical = preferences.scroll
    let pageLength = isVertical ? scrollView.bounds.height - insets.top - insets.bottom : scrollView.bounds.width
    let contentLength = isVertical ? scrollView.contentSize.height : scrollView.contentSize.width
    let offset = isVertical ? scrollView.contentOffset.y + insets.top : scrollView.contentOffset.x

    guard pageLength > 0, contentLength > 0 else { return nil }

    let columns = isVertical ? 1 : columnCount
    let screens = max(Int((contentLength / pageLength - 0.01).rounded(.up)), 1)
    let screen = min(max(Int((offset / pageLength).rounded()) + 1, 1), screens)
    let scrollableLength = contentLength - pageLength
    let fraction = scrollableLength > 0 ? min(max(offset / scrollableLength, 0), 1) : 1

    return ((screen - 1) * columns + 1, screens * columns, fraction)
  }

  private func paginationScrollView(in view: UIView) -> UIScrollView? {
    if let scrollView = view as? UIScrollView, !(scrollView.superview is WKWebView) {
      return scrollView
    }

    for subview in view.subviews {
      if let scrollView = paginationScrollView(in: subview) {
        return scrollView
      }
    }

    return nil
  }

  private func webViews(in view: UIView) -> [WKWebView] {
    if let webView = view as? WKWebView {
      return [webView]
    }
    return view.subviews.flatMap { webViews(in: $0) }
  }
}
