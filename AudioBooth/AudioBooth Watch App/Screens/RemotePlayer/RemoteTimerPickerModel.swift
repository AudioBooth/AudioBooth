import Foundation

final class RemoteTimerPickerModel: TimerPickerSheet.Model {
  private let connectivityManager = WatchConnectivityManager.shared

  override func onAppear() {
    Task {
      await sync(action: "get")
    }
  }

  override func onMinutesSelected(_ minutes: Int) {
    perform(action: "preset", value: minutes)
  }

  override func onChaptersSelected(_ count: Int) {
    perform(action: "chapter", value: count)
  }

  override func onCancelTapped() {
    perform(action: "cancel")
  }

  private func perform(action: String, value: Int? = nil) {
    isLoading = true

    Task {
      await sync(action: action, value: value)
      isLoading = false

      if errorMessage == nil {
        isPresented = false
      }
    }
  }

  private func sync(action: String, value: Int? = nil) async {
    guard let timer = await connectivityManager.sendSleepTimerCommand(action: action, value: value) else {
      errorMessage = String(localized: "Sleep timer isn't available on your iPhone right now.")
      return
    }

    current = timer.selection
    chapterEstimates = timer.chapterEstimates
    errorMessage = nil
  }
}
