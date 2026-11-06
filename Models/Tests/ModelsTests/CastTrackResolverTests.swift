import XCTest
@testable import Models

final class CastTrackResolverTests: XCTestCase {
  func testEmptyTracks() {
    let result = CastTrackResolver.trackAndOffset(for: 42, in: [])
    XCTAssertEqual(result.index, 0)
    XCTAssertEqual(result.offset, 42)
  }

  func testNegativeTime() {
    let intervals = [(startOffset: 0.0, duration: 100.0)]
    let result = CastTrackResolver.trackAndOffset(for: -10, in: intervals)
    XCTAssertEqual(result.index, 0)
    XCTAssertEqual(result.offset, 0)
  }

  func testSingleTrackOffset() {
    let intervals = [(startOffset: 0.0, duration: 300.0)]
    let result = CastTrackResolver.trackAndOffset(for: 125, in: intervals)
    XCTAssertEqual(result.index, 0)
    XCTAssertEqual(result.offset, 125)
  }

  func testMultiTrackBoundary() {
    let intervals = [
      (startOffset: 0.0, duration: 100.0),
      (startOffset: 100.0, duration: 200.0),
      (startOffset: 300.0, duration: 50.0),
    ]

    // Start of track 0
    let t0Start = CastTrackResolver.trackAndOffset(for: 0, in: intervals)
    XCTAssertEqual(t0Start.index, 0)
    XCTAssertEqual(t0Start.offset, 0)

    // Mid track 0
    let t0Mid = CastTrackResolver.trackAndOffset(for: 50, in: intervals)
    XCTAssertEqual(t0Mid.index, 0)
    XCTAssertEqual(t0Mid.offset, 50)

    // Exact boundary: start of track 1
    let t1Start = CastTrackResolver.trackAndOffset(for: 100, in: intervals)
    XCTAssertEqual(t1Start.index, 1)
    XCTAssertEqual(t1Start.offset, 0)

    // Mid track 1
    let t1Mid = CastTrackResolver.trackAndOffset(for: 150, in: intervals)
    XCTAssertEqual(t1Mid.index, 1)
    XCTAssertEqual(t1Mid.offset, 50)

    // Start of track 2
    let t2Start = CastTrackResolver.trackAndOffset(for: 300, in: intervals)
    XCTAssertEqual(t2Start.index, 2)
    XCTAssertEqual(t2Start.offset, 0)

    // Beyond total duration: clamps to end of last track
    let beyond = CastTrackResolver.trackAndOffset(for: 400, in: intervals)
    XCTAssertEqual(beyond.index, 2)
    XCTAssertEqual(beyond.offset, 50)
  }

  func testStreamURLConstruction() {
    let serverWithSlash = URL(string: "https://audiobooks.example.com/")!
    let url1 = CastTrackResolver.streamURL(serverURL: serverWithSlash, sessionID: "abc-123", trackIndex: 3)
    XCTAssertEqual(url1?.absoluteString, "https://audiobooks.example.com/public/session/abc-123/track/3")

    let serverWithoutSlash = URL(string: "https://audiobooks.example.com")!
    let url2 = CastTrackResolver.streamURL(serverURL: serverWithoutSlash, sessionID: "xyz-789", trackIndex: 0)
    XCTAssertEqual(url2?.absoluteString, "https://audiobooks.example.com/public/session/xyz-789/track/0")
  }

  func testTrackModelOverload() {
    let tracks = [
      Track(index: 0, startOffset: 0, duration: 60),
      Track(index: 1, startOffset: 60, duration: 120),
    ]
    let result = CastTrackResolver.trackAndOffset(for: 90, in: tracks)
    XCTAssertEqual(result.index, 1)
    XCTAssertEqual(result.offset, 30)
  }
}
