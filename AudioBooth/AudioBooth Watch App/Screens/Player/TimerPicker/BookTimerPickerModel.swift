import Foundation

final class BookTimerPickerModel: TimerPickerSheet.Model {
  private static let extendWindow: TimeInterval = 5 * 60

  weak var playerModel: BookPlayerModel?

  private var selection: TimerPickerSheet.Selection = .none
  private var chapterStopTime: Double = 0
  private var endDate = Date()
  private var expiredAt: Date?

  private var upcomingChapters: [WatchChapter] {
    guard let playerModel else { return [] }
    return playerModel.book.chapters.filter { playerModel.current < $0.end }
  }

  init(playerModel: BookPlayerModel) {
    self.playerModel = playerModel
    super.init()
  }

  override func onAppear() {
    guard let playerModel else { return }

    let speed = Double(playerModel.options.speed)
    let upcoming = upcomingChapters
    chapterEstimates = upcoming.prefix(max(1, upcoming.count - 1)).map { chapter in
      (chapter.end - playerModel.current) / speed
    }
  }

  override func onMinutesSelected(_ minutes: Int) {
    start(.duration(TimeInterval(minutes * 60)))
  }

  override func onChaptersSelected(_ count: Int) {
    start(.chapters(count))
  }

  override func onCancelTapped() {
    reset()
    isPresented = false
  }

  func onTimeUpdate() {
    guard playerModel?.isPlaying == true else { return }

    switch current {
    case .none, .endsAt:
      break

    case .duration:
      updateRemaining()

    case .chapters:
      let count = upcomingChapters.filter { $0.end <= chapterStopTime }.count

      if count > 0 {
        current = .chapters(count)
      } else {
        expire()
      }
    }
  }

  func onPlaybackStarted() {
    if case .duration = current, endDate <= Date() {
      current = .none
      expiredAt = endDate
    }

    if let expiredAt, Date().timeIntervalSince(expiredAt) <= Self.extendWindow {
      start(selection)
    }
  }

  func reset() {
    current = .none
    expiredAt = nil
  }

  private func start(_ selection: TimerPickerSheet.Selection) {
    self.selection = selection
    current = selection
    expiredAt = nil
    isPresented = false

    switch selection {
    case .none, .endsAt:
      break
    case .duration(let duration):
      endDate = Date().addingTimeInterval(duration)
      startTicking()
    case .chapters(let count):
      chapterStopTime = upcomingChapters.prefix(count).last?.end ?? 0
    }

    if playerModel?.isPlaying == false {
      playerModel?.togglePlayback()
    }
  }

  private func startTicking() {
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
      guard let self, case .duration = self.current else {
        timer.invalidate()
        return
      }
      self.updateRemaining()
    }
  }

  private func updateRemaining() {
    let remaining = endDate.timeIntervalSinceNow
    if remaining > 0 {
      current = .duration(remaining)
    } else {
      expire()
    }
  }

  private func expire() {
    if case .chapters = selection {
      selection = .chapters(1)
    }
    expiredAt = Date()
    current = .none

    if playerModel?.isPlaying == true {
      playerModel?.togglePlayback()
    }
  }
}
