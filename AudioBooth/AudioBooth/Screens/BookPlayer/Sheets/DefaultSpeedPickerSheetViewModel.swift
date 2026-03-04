import SwiftUI

final class DefaultSpeedPickerSheetViewModel: FloatPickerSheet.Model {
  init() {
    let current = UserDefaults.standard.double(forKey: "defaultPlaybackSpeed")
    let speed = current > 0 ? current : 1.0

    super.init(
      title: "Default Speed",
      value: speed,
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
    UserDefaults.standard.set(rounded, forKey: "defaultPlaybackSpeed")
  }
}
