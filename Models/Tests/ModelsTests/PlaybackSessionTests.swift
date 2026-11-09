import XCTest
@testable import Models

final class PlaybackSessionTests: XCTestCase {
  func testRemoteURLConstruction() {
    let baseURL = URL(string: "https://audiobooks.example.com/public/session/test-session-123")!
    let session = PlaybackSession(
      id: "test-session-123",
      libraryItemID: "item-1",
      startTime: 0,
      currentTime: 0,
      duration: 3600,
      baseURL: baseURL
    )

    let track0 = Track(index: 0, startOffset: 0, duration: 1800)
    let track1 = Track(index: 1, startOffset: 1800, duration: 1800)

    XCTAssertEqual(
      session.remoteURL(for: track0)?.absoluteString,
      "https://audiobooks.example.com/public/session/test-session-123/track/0"
    )
    XCTAssertEqual(
      session.remoteURL(for: track1)?.absoluteString,
      "https://audiobooks.example.com/public/session/test-session-123/track/1"
    )
  }

  func testURLWithLocalPathPrioritizesLocal() {
    let baseURL = URL(string: "https://audiobooks.example.com/public/session/test-session-123")!
    let session = PlaybackSession(
      id: "test-session-123",
      libraryItemID: "item-1",
      startTime: 0,
      currentTime: 0,
      duration: 3600,
      baseURL: baseURL
    )

    let localFile = URL(fileURLWithPath: "/tmp/audio/track0.mp3")
    let downloadedTrack = Track(index: 0, startOffset: 0, duration: 1800, localPath: localFile)

    XCTAssertEqual(session.url(for: downloadedTrack), localFile)
    XCTAssertEqual(
      session.remoteURL(for: downloadedTrack)?.absoluteString,
      "https://audiobooks.example.com/public/session/test-session-123/track/0"
    )
  }

  func testURLWithoutBaseURLReturnsNilForRemote() {
    let session = PlaybackSession(
      id: "local-only-session",
      libraryItemID: "item-2",
      startTime: 0,
      currentTime: 0,
      duration: 1000,
      baseURL: nil
    )

    let track = Track(index: 0, startOffset: 0, duration: 1000)
    XCTAssertNil(session.remoteURL(for: track))
    XCTAssertNil(session.url(for: track))
  }
}
