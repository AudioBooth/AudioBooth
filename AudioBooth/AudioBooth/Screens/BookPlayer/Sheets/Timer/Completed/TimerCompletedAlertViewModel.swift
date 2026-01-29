import Combine
import Foundation
import UIKit

final class TimerCompletedAlertViewModel: TimerCompletedAlertView.Model {
  private let onExtend: () -> Void
  private let onReset: () -> Void
  private var cancellables = Set<AnyCancellable>()

  init(extendAction: String, onExtend: @escaping () -> Void, onReset: @escaping () -> Void) {
    self.onExtend = onExtend
    self.onReset = onReset

    super.init(extendAction: extendAction)

    setupShakeObserver()
    setupForegroundObserver()
  }

  override func onExtendTapped() {
    onExtend()
  }

  override func onResetTapped() {
    onReset()
  }

  private func setupForegroundObserver() {
    NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
      .sink { [weak self] _ in
        guard let self, self.isExpired else { return }
        self.onResetTapped()
      }
      .store(in: &cancellables)
  }

  private func setupShakeObserver() {
    ShakeDetector.shared.shakePublisher
      .sink { [weak self] in
        guard let self else { return }
        if UserPreferences.shared.shakeSensitivity.isEnabled {
          self.onExtendTapped()
        }
      }
      .store(in: &cancellables)
  }
}
