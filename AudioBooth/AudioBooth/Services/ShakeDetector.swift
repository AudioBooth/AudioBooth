import Combine
import CoreMotion
import Foundation
import Logging
import UIKit

final class ShakeDetector {
  static let shared = ShakeDetector()

  private let motionManager = CMMotionManager()
  private var isMonitoring = false

  private let updateInterval: TimeInterval = 0.1
  private let shakeCooldown: TimeInterval = 0.5

  private var lastShakeAt: Date?

  private let shakeSubject = PassthroughSubject<Void, Never>()

  var shakePublisher: AnyPublisher<Void, Never> {
    shakeSubject.eraseToAnyPublisher()
  }

  private init() {}

  func startMonitoring() {
    let threshold = UserPreferences.shared.shakeSensitivity.threshold

    guard !isMonitoring, motionManager.isAccelerometerAvailable, threshold > 0 else { return }

    motionManager.accelerometerUpdateInterval = updateInterval
    motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
      guard let self, let data else { return }

      let acceleration = data.acceleration
      let gForce = sqrt(
        pow(acceleration.x, 2) + pow(acceleration.y, 2) + pow(acceleration.z, 2)
      )

      if gForce > threshold {
        self.handleShake()
      }
    }

    isMonitoring = true
    AppLogger.player.info("Shake detection started")
  }

  func stopMonitoring() {
    guard isMonitoring else { return }

    motionManager.stopAccelerometerUpdates()
    isMonitoring = false
    AppLogger.player.info("Shake detection stopped")
  }

  private func handleShake() {
    let now = Date()

    if let lastShakeAt, now.timeIntervalSince(lastShakeAt) < shakeCooldown {
      return
    }

    lastShakeAt = now

    shakeSubject.send()

    AppLogger.player.debug("Shake detected")
  }
}
