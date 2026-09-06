import Foundation
import Logging

enum NarrationSession {
  private static var previous: AsyncStream<Void>?

  nonisolated private static let maximumWaitForPreviousSession = Duration.seconds(20)

  static func begin(_ body: @Sendable @escaping () async -> Void) -> Task<Void, Never> {
    let earlier = previous
    let (finished, continuation) = AsyncStream<Void>.makeStream()
    previous = finished

    return Task.detached(priority: .utility) {
      defer { continuation.finish() }

      await waitForPreviousSession(earlier)
      guard !Task.isCancelled else { return }
      await body()
    }
  }

  nonisolated private static func waitForPreviousSession(_ earlier: AsyncStream<Void>?) async {
    guard let earlier else { return }

    let didFinish = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        for await _ in earlier {}
        return true
      }
      group.addTask {
        try? await Task.sleep(for: maximumWaitForPreviousSession)
        return false
      }

      let first = await group.next() ?? true
      group.cancelAll()
      return first
    }

    guard !didFinish else { return }
    AppLogger.readAlong.warning("Previous narration session never finished, starting a new one anyway")
  }
}
