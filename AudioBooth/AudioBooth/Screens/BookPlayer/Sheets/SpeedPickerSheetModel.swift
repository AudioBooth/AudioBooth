import Models
import SwiftUI

final class SpeedPickerSheetViewModel: FloatPickerSheet.Model {
  private let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")
  private let mediaProgress: MediaProgress?

  let player: AudioPlayer

  init(player: AudioPlayer, mediaProgress: MediaProgress? = nil) {
    self.mediaProgress = mediaProgress
    let fallback = UserDefaults.standard.double(forKey: "playbackSpeed")

    let speed: Float
    if let saved = mediaProgress?.playbackSpeed, saved > 0 {
      speed = Float(saved)
    } else {
      speed = fallback > 0 ? Float(fallback) : 1.0
    }

    sharedDefaults?.set(speed, forKey: "playbackSpeed")
    player.rate = speed

    self.player = player
    super.init(
      title: "Speed",
      value: Double(speed),
      range: 0.5...3.5,
      step: 0.05,
      presets: [0.7, 1.0, 1.2, 1.5, 1.7, 2.0],
      defaultValue: 1.0
    )
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
    let rounded = (newValue / 0.05).rounded() * 0.05
    value = rounded
    let floatValue = Float(rounded)

    mediaProgress?.playbackSpeed = rounded
    sharedDefaults?.set(floatValue, forKey: "playbackSpeed")

    player.rate = floatValue
  }
}
