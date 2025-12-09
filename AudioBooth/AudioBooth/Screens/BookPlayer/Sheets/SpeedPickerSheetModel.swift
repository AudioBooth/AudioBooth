import AVFoundation
import SwiftUI

final class SpeedPickerSheetViewModel: SpeedPickerSheet.Model {
  private let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")

  let player: AVPlayer

  init(player: AVPlayer) {
    let speed = UserDefaults.standard.float(forKey: "playbackSpeed")
    sharedDefaults?.set(speed, forKey: "playbackSpeed")

    player.defaultRate = speed > 0 ? speed : 1.0

    self.player = player
    super.init(playbackSpeed: player.defaultRate)
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
    sharedDefaults?.set(playbackSpeed, forKey: "playbackSpeed")

    player.defaultRate = roundedSpeed
    if player.rate > 0 {
      player.rate = roundedSpeed
    }
  }
}
