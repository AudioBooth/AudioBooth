import AVFoundation
import SwiftUI

final class SpeedPickerSheetViewModel: FloatPickerSheet.Model {
  private let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")

  let player: AVPlayer

  init(player: AVPlayer) {
    let speed = UserDefaults.standard.float(forKey: "playbackSpeed")
    sharedDefaults?.set(speed, forKey: "playbackSpeed")

    player.defaultRate = speed > 0 ? speed : 1.0

    self.player = player
    super.init(
      title: "Speed",
      value: Double(player.defaultRate),
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
    UserDefaults.standard.set(floatValue, forKey: "playbackSpeed")
    sharedDefaults?.set(floatValue, forKey: "playbackSpeed")

    player.defaultRate = floatValue
    if player.rate > 0 {
      player.rate = floatValue
    }
  }
}
