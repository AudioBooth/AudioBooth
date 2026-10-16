import Foundation
import Models
import ReadiumNavigator
import ReadiumShared

extension EbookReaderViewModel {
  private static let secondsBeforeRetargetingMediaOverlay: TimeInterval = 0.75
  private static let secondsBetweenMediaOverlayRefreshes: TimeInterval = 0.15

  var narrationPlayer: BookPlayerModel? {
    guard let bookID, let player = PlayerManager.shared.current as? BookPlayerModel, player.id == bookID else {
      return nil
    }
    return player
  }

  func setupMediaOverlay(for publication: Publication) async {
    guard navigator is EPUBNavigatorViewController,
      let bookID,
      let localBook = try? LocalBook.fetch(bookID: bookID),
      localBook.hasImportedNarration
    else {
      return
    }

    mediaOverlayTimeline = await MediaOverlayTimeline.load(
      from: publication,
      trackStartOffsets: localBook.orderedTracks.map(\.startOffset)
    )
  }

  func toggleMediaOverlayReadAlong() {
    if isFollowingMediaOverlay, narrationPlayer?.isPlaying == true {
      stopFollowingMediaOverlay()
      return
    }

    startFollowingMediaOverlay()

    if let narrationPlayer {
      if !narrationPlayer.isPlaying {
        narrationPlayer.onPlayTapped()
      }
    } else {
      Task { await playNarrationFromVisiblePage() }
    }
  }

  func stopFollowingMediaOverlay() {
    isFollowingMediaOverlay = false
    mediaOverlayFollowTask?.cancel()
    mediaOverlayFollowTask = nil
    tearDownReadAlong()
    updateAutoScroll()
  }

  private func refreshMediaOverlayHighlight() {
    guard readerSuspendedAt == nil,
      let timeline = mediaOverlayTimeline,
      let narrationPlayer,
      let index = timeline.clipIndex(at: narrationPlayer.secondsFromStartOfBook),
      index != mediaOverlayClipIndex
    else {
      return
    }

    mediaOverlayClipIndex = index
    let sentence = timeline.overlay.clips[index].text
    applyReadAlongDecorations(sentence: sentence, word: nil)

    if preferences.readAlongFollowsNarration {
      followNarration(sentence: sentence, word: nil)
    }
  }

  func mediaOverlayLocationChanged() {
    guard hasPositionedReader else {
      hasPositionedReader = true
      return
    }

    guard mediaOverlayTimeline != nil, narrationPlayer?.isPlaying == false, readAlongNavigationTask == nil else {
      return
    }

    mediaOverlayRetargetTask?.cancel()
    mediaOverlayRetargetTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.secondsBeforeRetargetingMediaOverlay))
      guard !Task.isCancelled else { return }
      await self?.retargetMediaOverlay()
    }
  }

  private func startFollowingMediaOverlay() {
    isFollowingMediaOverlay = true
    mediaOverlayFollowTask?.cancel()
    mediaOverlayClipIndex = nil
    mediaOverlayFollowTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        self.refreshMediaOverlayHighlight()
        try? await Task.sleep(for: .seconds(Self.secondsBetweenMediaOverlayRefreshes))
      }
    }
    updateAutoScroll()
  }

  private func playNarrationFromVisiblePage() async {
    guard let bookID,
      let timeline = mediaOverlayTimeline,
      let localBook = try? LocalBook.fetch(bookID: bookID)
    else {
      return
    }

    let index = await startClipIndex()

    PlayerManager.shared.setCurrent(localBook)
    narrationPlayer?.seekToTime(timeline.starts[index])
    PlayerManager.shared.play()
  }

  private func retargetMediaOverlay() async {
    guard readAlongNavigationTask == nil,
      let timeline = mediaOverlayTimeline,
      let narrationPlayer,
      !narrationPlayer.isPlaying,
      !narrationPlayer.isLoading,
      let currentIndex = timeline.clipIndex(at: narrationPlayer.secondsFromStartOfBook)
    else {
      return
    }

    let visible = await visibleClipIndices()
    guard let first = visible.first, !visible.contains(currentIndex),
      readAlongNavigationTask == nil, !narrationPlayer.isPlaying, !Task.isCancelled
    else {
      return
    }

    stopFollowingMediaOverlay()
    narrationPlayer.seekToTime(timeline.starts[first])
  }

  private func startClipIndex() async -> Int {
    if let visible = await visibleClipIndices().first {
      return visible
    }

    guard let overlay = mediaOverlayTimeline?.overlay,
      let publication,
      let href = navigator?.currentLocation?.href,
      let resourceIndex = publication.readingOrder.firstIndexWithHREF(href)
    else {
      return 0
    }

    return publication.readingOrder[resourceIndex...].lazy
      .compactMap({ overlay.firstClipIndex(in: $0.url()) }).first ?? 0
  }

  private func visibleClipIndices() async -> [Int] {
    guard let overlay = mediaOverlayTimeline?.overlay,
      let href = navigator?.currentLocation?.href,
      let navigator = navigator as? EPUBNavigatorViewController
    else {
      return []
    }

    let candidates = overlay.clipIndices(in: href)
    let ids = candidates.map { overlay.clips[$0].fragment }

    guard !candidates.isEmpty,
      let json = try? JSONEncoder().encode(ids),
      let idList = String(data: json, encoding: .utf8)
    else {
      return []
    }

    let script = """
      (function(ids) {
        return ids.filter(function(id) {
          const element = document.getElementById(id);
          if (!element) return false;
          const rect = element.getBoundingClientRect();
          return rect.bottom > 0 && rect.right > 0 && rect.top < window.innerHeight && rect.left < window.innerWidth;
        });
      })(\(idList));
      """

    guard case .success(let value) = await navigator.evaluateJavaScript(script),
      let visibleIDs = value as? [String]
    else {
      return []
    }

    let visible = Set(visibleIDs)
    return candidates.filter { visible.contains(overlay.clips[$0].fragment) }
  }
}
