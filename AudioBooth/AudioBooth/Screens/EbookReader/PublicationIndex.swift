import ReadiumShared

struct PublicationIndex {
  let positions: [Locator]
  private let readingOrderIndexes: [String: Int]
  private let positionsByHREF: [String: [Locator]]

  init(publication: Publication? = nil, positions: [Locator] = []) {
    self.positions = positions
    readingOrderIndexes = Dictionary(
      (publication?.readingOrder ?? []).enumerated().map { ($1.url().normalized.string, $0) },
      uniquingKeysWith: { first, _ in first }
    )
    positionsByHREF = Dictionary(grouping: positions, by: { $0.href.string })
  }

  func readingOrderIndex(of href: some URLConvertible) -> Int? {
    let url = href.anyURL.normalized
    return readingOrderIndexes[url.string]
      ?? readingOrderIndexes[url.removingQuery().removingFragment().string]
  }

  func positions(in href: String) -> [Locator] {
    positionsByHREF[href] ?? []
  }

  func firstPosition(in href: String) -> Int? {
    positionsByHREF[href]?.first?.locations.position
  }
}
