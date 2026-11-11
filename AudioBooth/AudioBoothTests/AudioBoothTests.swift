import Combine
import Foundation
import Testing
@testable import AudioBooth

@Suite("Cast & Playback Tests")
struct AudioBoothTests {
  @Test("Module can be imported and verified")
  func testModuleImport() async throws {
    #expect(true)
  }

  @Test("CastManager initial state is disconnected and idle")
  @MainActor
  func testCastManagerInitialState() throws {
    #if canImport(GoogleCast) && !os(watchOS)
    let cast = CastManager.shared
    #expect(!cast.isConnected)
    #expect(!cast.isPlaying)
    #expect(cast.currentPosition == 0)
    #expect(cast.currentStreamURL == nil)
    #endif
  }

  @Test("BookPlayer Model willSet triggers objectWillChange on state changes")
  @MainActor
  func testBookPlayerModelChangeNotification() throws {
    var model = BookPlayer.Model.mock
    var notified = false
    let cancellable = model.objectWillChange.sink {
      notified = true
    }
    model.isPlaying = true
    #expect(notified)
    _ = cancellable
  }
}
