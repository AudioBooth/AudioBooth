import AVFoundation
import SwiftUI

@MainActor
final class SpeedPickerSheetViewModel: SpeedPickerSheet.Model {
  let player: AVPlayer

  init(player: AVPlayer) {
    let speed = UserDefaults.standard.float(forKey: "playbackSpeed")

    self.player = player
    super.init(playbackSpeed: speed > 0 ? speed : 1.0)
  }

  override func onSpeedIncrease() {
    let newSpeed = min(playbackSpeed + 0.05, 3.5)
    onSpeedChanged(newSpeed)
  }

  override func onSpeedDecrease() {
    let newSpeed = max(playbackSpeed - 0.05, 0.5)
    onSpeedChanged(newSpeed)
  }

  override func onSpeedChanged(_ speed: Float) {
    let roundedSpeed = round(speed / 0.05) * 0.05
    playbackSpeed = roundedSpeed
    UserDefaults.standard.set(playbackSpeed, forKey: "playbackSpeed")

    if player.rate > 0 {
      player.rate = roundedSpeed
    }
  }
}
