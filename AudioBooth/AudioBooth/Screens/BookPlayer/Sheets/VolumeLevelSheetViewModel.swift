import SwiftUI

final class VolumeLevelSheetViewModel: FloatPickerSheet.Model {
  private static let defaultPresets: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
  private static let presetsKey = "volumePresets"

  private let player: AudioPlayer
  private let userPreferences = UserPreferences.shared

  init(player: AudioPlayer) {
    self.player = player

    let savedPresets = UserDefaults.standard.array(forKey: Self.presetsKey) as? [Double]
    let presets = savedPresets ?? Self.defaultPresets

    super.init(
      title: "Volume",
      value: userPreferences.volumeLevel,
      range: 0.1...3.0,
      step: 0.05,
      presets: presets,
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

  override func onPresetChanged(at index: Int, newValue: Double) {
    super.onPresetChanged(at: index, newValue: newValue)
    UserDefaults.standard.set(presets, forKey: Self.presetsKey)
  }
}
