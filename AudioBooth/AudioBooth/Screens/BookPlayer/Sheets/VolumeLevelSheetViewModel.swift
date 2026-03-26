import SwiftUI

final class VolumeLevelSheetViewModel: FloatPickerSheet.Model {
  private let player: AudioPlayer
  private let userPreferences = UserPreferences.shared

  init(player: AudioPlayer) {
    self.player = player
    super.init(
      title: "Volume",
      value: userPreferences.volumeLevel,
      range: 0.1...3.0,
      step: 0.05,
      presets: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
      defaultValue: 1.0
    )
  }

  override func onIncrease() {
    let newLevel = min(value + 0.05, 3.0)
    onValueChanged(newLevel)
  }

  override func onDecrease() {
    let newLevel = max(value - 0.05, 0.1)
    onValueChanged(newLevel)
  }

  override func onValueChanged(_ level: Double) {
    let rounded = (level / 0.05).rounded() * 0.05
    value = rounded
    userPreferences.volumeLevel = rounded
    player.volume = Float(rounded)
  }
}
