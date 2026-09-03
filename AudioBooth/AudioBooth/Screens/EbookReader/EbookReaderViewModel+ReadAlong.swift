import API
import Foundation
import Models
import ReadiumNavigator
import ReadiumShared
import Speech
import UIKit

extension EbookReaderViewModel {
  private static let readAlongDecorationGroup = "readAlong"
  private static let sentenceDecorationID = "readAlong.sentence"
  private static let wordDecorationID = "readAlong.word"
  private static let minimumSecondsBetweenDecorations: TimeInterval = 0.2
  private static let minimumSecondsBetweenNavigations: TimeInterval = 0.3
  private static let secondsAwaitingDecorationAfterJump: TimeInterval = 0.35
  private static let secondsSettlingAfterScroll: TimeInterval = 0.4

  var isReadAlongSupported: Bool {
    guard #available(iOS 26.0, *), SpeechTranscriber.isAvailable else { return false }
    return navigator is DecorableNavigator && matchingSession() != nil
  }

  func toggleReadAlong() {
    guard let readAlong else {
      startReadAlong()
      return
    }
    readAlong.toggle()
  }

  func tearDownReadAlong() {
    readAlong?.onActiveChanged = nil
    readAlong?.stop()
    readAlong = nil
    readAlongDecorationTask?.cancel()
    readAlongDecorationTask = nil
    pendingReadAlongDecorations = nil
    lastReadAlongDecorationAt = nil
    cancelReadAlongNavigation()
    (navigator as? DecorableNavigator)?.apply(decorations: [], in: Self.readAlongDecorationGroup)
  }

  func syncReadAlongPreferences() {
    readAlong?.followsNarration = preferences.readAlongFollowsNarration
    readAlong?.highlightsWord = preferences.readAlongHighlightsWord
  }

  private func startReadAlong() {
    guard #available(iOS 26.0, *) else {
      Toast(error: String(localized: "Read Along requires iOS 26 or later.")).show()
      return
    }

    guard let publication else { return }

    guard let player = PlayerManager.shared.current, matchingSession() != nil else {
      Toast(error: String(localized: "Play this book's audiobook to use Read Along.")).show()
      return
    }

    guard let source = narrationSource() else {
      Toast(error: String(localized: "Download this audiobook to use Read Along.")).show()
      return
    }

    let coordinator = ReadAlongCoordinator(
      publication: publication,
      source: source,
      playhead: { [weak player] in
        guard let player, PlayerManager.shared.current === player else { return nil }
        return player.secondsFromStartOfBook
      }
    )

    coordinator.followsNarration = preferences.readAlongFollowsNarration
    coordinator.highlightsWord = preferences.readAlongHighlightsWord

    coordinator.onHighlightChanged = { [weak self] sentence, word in
      self?.applyReadAlongDecorations(sentence: sentence, word: word)
    }

    coordinator.onFollow = { [weak self] sentence, word in
      self?.followNarration(sentence: sentence, word: word)
    }

    coordinator.onActiveChanged = { [weak self] in
      guard let self else { return }
      if self.readAlong?.status.isActive != true {
        self.cancelReadAlongNavigation()
      }
      self.updateAutoScroll()
    }

    readAlong = coordinator
    coordinator.start()
  }

  private func matchingSession() -> PlaybackSession? {
    guard let bookID,
      PlayerManager.shared.current?.id == bookID,
      let session = SessionManager.shared.current,
      session.libraryItemID == bookID
    else {
      return nil
    }

    return session
  }

  private func narrationSource() -> NarrationSource? {
    guard let session = matchingSession() else { return nil }

    let tracks = session.tracks
      .sorted { $0.startOffset < $1.startOffset }
      .compactMap { track -> NarrationSource.Track? in
        guard let url = track.localPath else { return nil }
        return NarrationSource.Track(
          url: url,
          secondsFromStartOfBook: track.startOffset,
          duration: track.duration
        )
      }

    guard tracks.count == session.tracks.count, !tracks.isEmpty else { return nil }
    return NarrationSource(tracks: tracks)
  }

  private func applyReadAlongDecorations(sentence: Locator?, word: Locator?) {
    pendingReadAlongDecorations = [
      sentence.map {
        Decoration(id: Self.sentenceDecorationID, locator: $0, style: .highlight(tint: .systemYellow))
      },
      word.map {
        Decoration(id: Self.wordDecorationID, locator: $0, style: .underline(tint: .tintColor))
      },
    ].compactMap { $0 }

    flushReadAlongDecorations()
  }

  private func flushReadAlongDecorations() {
    guard readAlongDecorationTask == nil else { return }

    readAlongDecorationTask = Task { [weak self] in
      while let self, let decorations = self.pendingReadAlongDecorations {
        if let last = self.lastReadAlongDecorationAt {
          let sinceLast = Date().timeIntervalSince(last)
          if sinceLast < Self.minimumSecondsBetweenDecorations {
            try? await Task.sleep(for: .seconds(Self.minimumSecondsBetweenDecorations - sinceLast))
            continue
          }
        }

        self.pendingReadAlongDecorations = nil
        self.lastReadAlongDecorationAt = Date()
        (self.navigator as? DecorableNavigator)?
          .apply(decorations: decorations, in: Self.readAlongDecorationGroup)
      }

      self?.readAlongDecorationTask = nil
    }
  }

  private func followNarration(sentence: Locator, word: Locator?) {
    guard navigator != nil else {
      readAlong?.narrationDidLand()
      return
    }

    pendingReadAlongNavigation = preferences.scroll ? sentence : (word ?? sentence)
    flushReadAlongNavigation()
  }

  private func cancelReadAlongNavigation() {
    readAlongNavigationTask?.cancel()
    readAlongNavigationTask = nil
    pendingReadAlongNavigation = nil
  }

  private func flushReadAlongNavigation() {
    guard readAlongNavigationTask == nil else { return }

    readAlongNavigationTask = Task { [weak self] in
      while let self, !Task.isCancelled, let destination = self.pendingReadAlongNavigation {
        self.pendingReadAlongNavigation = nil
        await self.navigate(to: destination)
        self.readAlong?.narrationDidLand()
        try? await Task.sleep(for: .seconds(Self.minimumSecondsBetweenNavigations))
      }

      self?.readAlongNavigationTask = nil
    }
  }

  private func navigate(to locator: Locator) async {
    guard let navigator else { return }

    if preferences.scroll, await scrollNarrationIntoView() { return }

    await navigator.go(to: locator, options: NavigatorGoOptions(animated: false))

    guard preferences.scroll else { return }
    try? await Task.sleep(for: .seconds(Self.secondsAwaitingDecorationAfterJump))
    _ = await scrollNarrationIntoView()
  }

  private func scrollNarrationIntoView() async -> Bool {
    guard let scrollView = followingScrollView(), let place = await narrationPlaceOnScreen() else {
      return false
    }

    guard let restingPlace = scrollView.restingPlace(forNarrationAt: place) else { return true }

    let offset = (scrollView.contentOffset.y + place - restingPlace)
      .clamped(to: scrollView.reachableVerticalOffsets)
    scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: offset), animated: true)
    try? await Task.sleep(for: .seconds(Self.secondsSettlingAfterScroll))
    return true
  }

  private func narrationPlaceOnScreen() async -> CGFloat? {
    guard let navigator = navigator as? EPUBNavigatorViewController else { return nil }

    let measurement = """
      (function() {
        var items = readium.getDecorations('\(Self.readAlongDecorationGroup)').items;
        var sentence = items.find(function(each) {
          return each.decoration.id === '\(Self.sentenceDecorationID)';
        });
        return sentence ? sentence.range.getBoundingClientRect().top : null;
      })();
      """

    guard case let .success(measured) = await navigator.evaluateJavaScript(measurement),
      let place = measured as? Double
    else {
      return nil
    }

    return CGFloat(place)
  }

  private func followingScrollView() -> UIScrollView? {
    if let viewController = navigator as? UIViewController {
      updateCurrentScrollView(in: viewController.view)
    }
    return currentScrollView
  }
}

private extension UIScrollView {
  private static let pointsBelowReadableTop: CGFloat = 12
  private static let pointsKeptBelowNarration: CGFloat = 80

  var reachableVerticalOffsets: ClosedRange<CGFloat> {
    let topmost = -contentInset.top
    let bottommost = contentSize.height - bounds.height + contentInset.bottom
    return topmost...max(topmost, bottommost)
  }

  func restingPlace(forNarrationAt place: CGFloat) -> CGFloat? {
    let readableTop = contentInset.top
    let readableBottom = bounds.height - contentInset.bottom
    guard place < readableTop || place > readableBottom - Self.pointsKeptBelowNarration else {
      return nil
    }

    return readableTop + Self.pointsBelowReadableTop
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
