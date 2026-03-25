import SwiftUI

final class EqualizerSheetViewModel: EqualizerSheet.Model {
  private let player: AudioPlayer
  private let preferences = UserPreferences.shared
  private var saveTask: Task<Void, Never>?

  init(player: AudioPlayer) {
    self.player = player

    let settings = UserPreferences.shared.equalizerSettings
    player.isEQEnabled = settings.isEnabled
    player.setEQPreamp(settings.preamp)
    for (i, gain) in settings.bandGains.enumerated() {
      player.setEQBand(i, gain: gain)
    }

    super.init(
      isEnabled: settings.isEnabled,
      preamp: settings.preamp,
      bandGains: settings.bandGains,
      presets: EqualizerSheet.defaultPresets
    )
  }

  override func onToggleEnabled(_ enabled: Bool) {
    isEnabled = enabled
    player.isEQEnabled = enabled
    saveSettings()
  }

  override func onPreampChanged(_ value: Float) {
    preamp = value
    player.setEQPreamp(value)
    saveSettings()
  }

  override func onBandChanged(_ index: Int, gain: Float) {
    bandGains[index] = gain
    player.setEQBand(index, gain: gain)
    saveSettings()
  }

  override func onPresetSelected(_ preset: EqualizerSheet.Preset) {
    for (i, gain) in preset.gains.enumerated() {
      bandGains[i] = gain
      player.setEQBand(i, gain: gain)
    }
    saveSettings()
  }

  private func saveSettings() {
    saveTask?.cancel()
    saveTask = Task {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      preferences.equalizerSettings = EqualizerSettings(
        isEnabled: isEnabled,
        preamp: preamp,
        bandGains: bandGains
      )
    }
  }
}
