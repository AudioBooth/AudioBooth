import Foundation

extension MediaProgress {
  public static func mock(
    bookID: String = "mock-book-id",
    id: String? = "mock-progress-id",
    lastPlayedAt: Date = Date(),
    currentTime: TimeInterval = 300,
    duration: TimeInterval = 3600,
    progress: Double = 0.5,
    isFinished: Bool = false,
    lastUpdate: Date = Date()
  ) -> MediaProgress {
    MediaProgress(
      bookID: bookID,
      id: id,
      lastPlayedAt: lastPlayedAt,
      currentTime: currentTime,
      duration: duration,
      progress: progress,
      isFinished: isFinished,
      lastUpdate: lastUpdate
    )
  }

  public static var mockInProgress: MediaProgress {
    mock(
      bookID: "book-in-progress",
      currentTime: 1200,
      duration: 7200,
      progress: 0.33,
      isFinished: false
    )
  }

  public static var mockFinished: MediaProgress {
    mock(
      bookID: "book-finished",
      currentTime: 5400,
      duration: 5400,
      progress: 1.0,
      isFinished: true
    )
  }

  public static var mockJustStarted: MediaProgress {
    mock(
      bookID: "book-just-started",
      currentTime: 30,
      duration: 10800,
      progress: 0.003,
      isFinished: false
    )
  }

  public static var mockAlmostDone: MediaProgress {
    mock(
      bookID: "book-almost-done",
      currentTime: 9500,
      duration: 10000,
      progress: 0.95,
      isFinished: false
    )
  }

  public static var mockMultiple: [MediaProgress] {
    [
      mockJustStarted,
      mockInProgress,
      mockAlmostDone,
      mockFinished,
    ]
  }

  public static var mockRandom: MediaProgress {
    let duration = TimeInterval.random(in: 1800...43200)
    let progress = Double.random(in: 0...1)
    let currentTime = duration * progress
    let isFinished = progress >= 0.99

    return mock(
      bookID: "random-book-\(UUID().uuidString)",
      id: "progress-\(UUID().uuidString)",
      lastPlayedAt: Date().addingTimeInterval(-TimeInterval.random(in: 0...604800)),
      currentTime: currentTime,
      duration: duration,
      progress: progress,
      isFinished: isFinished,
      lastUpdate: Date().addingTimeInterval(-TimeInterval.random(in: 0...86400))
    )
  }

  public static func mockRandomMultiple(count: Int = 10) -> [MediaProgress] {
    (0..<count).map { _ in mockRandom }
  }
}
