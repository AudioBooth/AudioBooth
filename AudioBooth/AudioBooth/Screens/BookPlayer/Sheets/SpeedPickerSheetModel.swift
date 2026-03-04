import AVFoundation
import SwiftUI

final class SpeedPickerSheetViewModel: FloatPickerSheet.Model {
  private let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")
  private let bookID: String?

  let player: AVPlayer

  init(player: AVPlayer, bookID: String? = nil) {
    self.bookID = bookID

    let defaultSpeed = UserDefaults.standard.double(forKey: "defaultPlaybackSpeed")
    let fallback = defaultSpeed > 0 ? defaultSpeed : 1.0

    let speed: Float
    if let bookID {
      let saved = UserDefaults.standard.float(forKey: "bookSpeed_\(bookID)")
      speed = saved > 0 ? saved : Float(fallback)
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

    if let bookID {
      UserDefaults.standard.set(floatValue, forKey: "bookSpeed_\(bookID)")
    }
    sharedDefaults?.set(floatValue, forKey: "playbackSpeed")

    player.defaultRate = floatValue
    if player.rate > 0 {
      player.rate = floatValue
    }
  }
}
