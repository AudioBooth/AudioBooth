import AVFoundation
import Combine
import Models
import SwiftUI

final class SpeedPickerSheetViewModel: FloatPickerSheet.Model {
  private let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")
  private let mediaProgress: MediaProgress?
  private let preferences = UserPreferences.shared
  private var cancellables = Set<AnyCancellable>()

  let player: AVPlayer

  init(player: AVPlayer, mediaProgress: MediaProgress? = nil) {
    self.mediaProgress = mediaProgress

    let defaultSpeed = UserDefaults.standard.double(forKey: "defaultPlaybackSpeed")
    let fallback = defaultSpeed > 0 ? defaultSpeed : 1.0

    let speed: Float
    if let saved = mediaProgress?.playbackSpeed, saved > 0 {
      speed = Float(saved)
    } else {
      speed = Float(fallback)
    }

    sharedDefaults?.set(speed, forKey: "playbackSpeed")
    player.defaultRate = speed

    self.player = player
    super.init(
      title: "Speed",
      value: Double(speed),
      range: 0.5...3.5,
      step: 0.05,
      presets: [0.7, 1.0, 1.2, 1.5, 1.7, 2.0],
      defaultValue: 1.0
    )

    observeDefaultSpeedChanges()
  }

  private func observeDefaultSpeedChanges() {
    preferences.objectWillChange
      .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        guard let self,
          mediaProgress?.playbackSpeed == nil || mediaProgress?.playbackSpeed == 0
        else { return }

        let newDefault = preferences.defaultPlaybackSpeed
        guard newDefault > 0 else { return }
        applySpeed(newDefault)
      }
      .store(in: &cancellables)
  }

  private func applySpeed(_ newValue: Double) {
    let rounded = (newValue / 0.05).rounded() * 0.05
    value = rounded
    let floatValue = Float(rounded)

    sharedDefaults?.set(floatValue, forKey: "playbackSpeed")
    player.defaultRate = floatValue
    if player.rate > 0 {
      player.rate = floatValue
    }
  }

  override func onIncrease() {
    let newSpeed = min(value + 0.05, 3.5)
    onValueChanged(newSpeed)
  }

  override func onDecrease() {
    let newSpeed = max(value - 0.05, 0.5)
    onValueChanged(newSpeed)
  }

  override func onValueChanged(_ newValue: Double) {
    applySpeed(newValue)
    mediaProgress?.playbackSpeed = value
  }
}
