import SwiftUI

final class EqualizerSheetViewModel: EqualizerSheet.Model {
  private static let presetsKey = "equalizerPresets"

  private let player: AudioPlayer
  private let preferences = UserPreferences.shared
  private var saveTask: Task<Void, Never>?

  init(player: AudioPlayer) {
    self.player = player

    let settings = UserPreferences.shared.equalizerSettings
    player.setEQPreamp(settings.preamp)
    for (i, gain) in settings.bandGains.enumerated() {
      player.setEQBand(i, gain: gain)
    }

    let leveling = UserPreferences.shared.levelingStrength
    player.setLevelingStrength(leveling)
    player.setEQEnabled(settings.isEnabled)

    super.init(
      isEnabled: settings.isEnabled,
      levelingStrength: leveling,
      preamp: settings.preamp,
      bandGains: settings.bandGains,
      presets: Self.loadCustomPresets() + EqualizerSheet.defaultPresets
    )
  }

  override func onToggleEnabled(_ enabled: Bool) {
    isEnabled = enabled
    player.setEQEnabled(enabled)
    saveSettings()
  }

  override func onLevelingStrengthChanged(_ strength: LevelingStrength) {
    levelingStrength = strength
    player.setLevelingStrength(strength)
    preferences.levelingStrength = strength
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
    preamp = preset.preamp
    player.setEQPreamp(preset.preamp)
    for (i, gain) in preset.gains.enumerated() where bandGains.indices.contains(i) {
      bandGains[i] = gain
      player.setEQBand(i, gain: gain)
    }
    if let leveling = preset.levelingStrength {
      onLevelingStrengthChanged(leveling)
    }
    saveSettings()
  }

  override func onSavePreset(named name: String) {
    guard isValidPresetName(name) else { return }

    let preset = EqualizerSheet.Preset(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      preamp: preamp,
      gains: bandGains,
      levelingStrength: levelingStrength,
      isCustom: true
    )

    var customPresets = presets.filter(\.isCustom)
    if let index = customPresets.firstIndex(where: { $0.name == preset.name }) {
      customPresets[index] = preset
    } else {
      customPresets.append(preset)
    }
    updateCustomPresets(customPresets)
  }

  override func onDeletePreset(_ preset: EqualizerSheet.Preset) {
    updateCustomPresets(presets.filter { $0.isCustom && $0.name != preset.name })
  }

  private func updateCustomPresets(_ customPresets: [EqualizerSheet.Preset]) {
    presets = customPresets + EqualizerSheet.defaultPresets
    guard let data = try? JSONEncoder().encode(customPresets) else { return }
    UserDefaults.standard.set(data, forKey: Self.presetsKey)
  }

  private static func loadCustomPresets() -> [EqualizerSheet.Preset] {
    guard let data = UserDefaults.standard.data(forKey: presetsKey),
      let presets = try? JSONDecoder().decode([EqualizerSheet.Preset].self, from: data)
    else { return [] }
    return presets
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
