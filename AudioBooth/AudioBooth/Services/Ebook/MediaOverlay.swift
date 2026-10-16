import Foundation
import ReadiumShared

nonisolated struct MediaOverlay: Sendable {
  struct Clip: Sendable {
    let text: Locator
    let fragment: String
    let audio: AnyURL
    let begin: TimeInterval
  }

  let clips: [Clip]

  private let firstClipIndices: [String: Int]

  init(clips: [Clip]) {
    self.clips = clips

    firstClipIndices = Dictionary(
      clips.enumerated().map { ($0.element.text.href.normalized.string, $0.offset) },
      uniquingKeysWith: { first, _ in first }
    )
  }

  @concurrent
  static func load(from publication: Publication) async -> MediaOverlay? {
    var clips: [Clip] = []
    for link in publication.readingOrder {
      guard case .success(let document?) = await publication.guidedNavigationDocument(for: link.url()) else {
        continue
      }
      clips += document.guided.flatMap { self.clips(in: $0, publication: publication) }
    }

    return clips.isEmpty ? nil : MediaOverlay(clips: clips)
  }

  var audioFiles: [AnyURL] {
    var seen = Set<String>()
    return clips.compactMap { seen.insert($0.audio.string).inserted ? $0.audio : nil }
  }

  func firstClipIndex(in href: AnyURL) -> Int? {
    firstClipIndices[href.removingFragment().normalized.string]
  }

  func clipIndices(in href: AnyURL) -> Range<Int> {
    guard let first = firstClipIndex(in: href) else { return 0..<0 }
    let resource = clips[first].text.href
    return clips.indices[first...].prefix { clips[$0].text.href.isEquivalentTo(resource) }
  }

  private static func clips(in object: GuidedNavigationObject, publication: Publication) -> [Clip] {
    let children = object.children.flatMap { clips(in: $0, publication: publication) }

    guard let text = object.refs?.text,
      let fragment = text.fragment,
      let audio = object.refs?.audio,
      let link = publication.readingOrder.firstWithHREF(text.removingFragment())
    else {
      return children
    }

    let locator = Locator(
      href: link.url(),
      mediaType: link.mediaType ?? .xhtml,
      title: link.title,
      locations: Locator.Locations(fragments: [fragment])
    )
    let clip = Clip(
      text: locator,
      fragment: fragment,
      audio: audio.removingFragment().normalized,
      begin: begin(of: audio)
    )
    return [clip] + children
  }

  private static func begin(of audio: AnyURL) -> TimeInterval {
    guard let fragment = audio.fragment, fragment.hasPrefix("t=") else { return 0 }
    return Double(fragment.dropFirst(2).prefix { $0 != "," }) ?? 0
  }
}
