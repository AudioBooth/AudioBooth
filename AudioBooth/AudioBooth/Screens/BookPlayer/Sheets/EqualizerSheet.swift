import Combine
import SwiftUI

struct EqualizerSheet: View {
  @ObservedObject var model: Model

  @State private var isSavingPreset = false
  @State private var presetName = ""

  #if targetEnvironment(macCatalyst)
  private let headerTrailingInset: CGFloat = 44
  #else
  private let headerTrailingInset: CGFloat = 0
  #endif

  var body: some View {
    VStack(spacing: 0) {
      headerView
        .padding(.horizontal, 24)
        .padding(.top, 24)

      settingsView
        .opacity(model.isEnabled ? 1 : 0.5)
        .disabled(!model.isEnabled)
    }
    .alert("Save Preset", isPresented: $isSavingPreset) {
      TextField("Preset Name", text: $presetName)
      Button("Cancel", role: .cancel) {}
      Button("Save") { model.onSavePreset(named: presetName) }
        .disabled(!model.isValidPresetName(presetName))
    }
  }

  private var headerView: some View {
    HStack {
      Text("Equalizer")
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundColor(.primary)

      Spacer()

      Toggle(
        "Equalizer",
        isOn: Binding(
          get: { model.isEnabled },
          set: { model.onToggleEnabled($0) }
        )
      )
      .labelsHidden()
      .toggleStyle(.switch)
    }
    .padding(.trailing, headerTrailingInset)
  }

  private var settingsView: some View {
    VStack(spacing: 0) {
      preampView
        .padding(.horizontal, 24)
        .padding(.top, 24)

      bandsView
        .padding(.top, 24)

      presetsView
        .padding(.top, 20)
        .padding(.horizontal, 16)

      Divider()
        .padding(.horizontal, 24)
        .padding(.top, 24)

      levelingView
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 40)
    }
  }

  private var levelingView: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Volume Leveling")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.primary)

        Text("Evens out loud and quiet passages")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      Picker(
        "",
        selection: Binding(
          get: { model.levelingStrength },
          set: { model.onLevelingStrengthChanged($0) }
        )
      ) {
        ForEach(LevelingStrength.allCases) { strength in
          Text(strength.displayName).tag(strength)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
    }
  }

  private var preampView: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Preamplifier")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.primary)

        Spacer()

        Text(verbatim: "\(formattedGain(model.preamp)) dB")
          .font(.system(size: 13, weight: .medium).monospacedDigit())
          .foregroundColor(.primary)
      }

      Slider(
        value: Binding(
          get: { model.preamp },
          set: { model.onPreampChanged($0) }
        ),
        in: -12...12,
        step: 0.5
      )
    }
  }

  private var bandsView: some View {
    HStack(alignment: .center, spacing: 0) {
      ForEach(0..<model.bandGains.count, id: \.self) { index in
        VStack(spacing: 8) {
          Text(verbatim: formattedGain(model.bandGains[index]))
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundColor(.primary)
            .frame(width: 32)

          VerticalSlider(
            value: Binding(
              get: { model.bandGains[index] },
              set: { model.onBandChanged(index, gain: $0) }
            ),
            range: -12...12
          )
          .frame(height: 160)

          Text(model.bandLabels[index])
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
      }
    }
    .padding(.horizontal, 8)
  }

  private var presetsView: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Presets")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.primary)

        Spacer()

        Button(
          action: {
            presetName = ""
            isSavingPreset = true
          },
          label: {
            Image(systemName: "plus")
              .font(.system(size: 14, weight: .semibold))
          }
        )
        .accessibilityLabel("Save Preset")
        .disabled(model.selectedPreset != nil)
      }

      FlowLayout(spacing: 8) {
        ForEach(model.presets) { preset in
          let isSelected = model.selectedPreset == preset.name
          Button(action: { model.onPresetSelected(preset) }) {
            Text(preset.name)
              .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
              .foregroundColor(isSelected ? .white : .primary)
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background {
                if isSelected {
                  RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
                } else {
                  RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.08))
                }
              }
          }
          .buttonStyle(.plain)
          .contextMenu {
            if preset.isCustom {
              Button("Delete", systemImage: "trash", role: .destructive) {
                model.onDeletePreset(preset)
              }
            }
          }
        }
      }
    }
  }

  private func formattedGain(_ gain: Float) -> String {
    let rounded = (gain * 2).rounded() / 2
    if rounded == 0 { return "0" }
    return String(format: "%+.1f", rounded)
  }
}

private struct VerticalSlider: View {
  @Binding var value: Float
  let range: ClosedRange<Float>
  var body: some View {
    GeometryReader { geo in
      let height = geo.size.height
      let center = height / 2
      let normalized = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
      let thumbY = height - (normalized * height)
      let barHeight = abs(thumbY - center)
      let barOffset = (thumbY + center) / 2 - center

      ZStack {
        RoundedRectangle(cornerRadius: 2)
          .fill(Color.primary.opacity(0.15))
          .frame(width: 4)

        RoundedRectangle(cornerRadius: 2)
          .fill(Color.accentColor)
          .frame(width: 4, height: barHeight)
          .offset(y: barOffset)

        Circle()
          .fill(Color.white)
          .shadow(color: .black.opacity(0.2), radius: 2)
          .frame(width: 20, height: 20)
          .offset(y: thumbY - center)
      }
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { drag in
            let fraction = 1 - (drag.location.y / height)
            let clamped = min(max(fraction, 0), 1)
            value = range.lowerBound + Float(clamped) * (range.upperBound - range.lowerBound)
          }
      )
    }
  }
}

extension EqualizerSheet {
  struct Preset: Identifiable, Codable, Equatable {
    let name: String
    let preamp: Float
    let gains: [Float]
    var levelingStrength: LevelingStrength? = nil
    var isCustom: Bool = false
    var id: String { name }
  }

  @Observable
  class Model: ObservableObject {
    var isPresented: Bool
    var isEnabled: Bool
    var levelingStrength: LevelingStrength
    var preamp: Float
    var bandGains: [Float]
    var bandLabels: [String]
    var presets: [Preset]

    var selectedPreset: String? {
      presets.first { preset in
        preset.gains == bandGains && preset.preamp == preamp
          && (preset.levelingStrength == nil || preset.levelingStrength == levelingStrength)
      }?.name
    }

    func isValidPresetName(_ name: String) -> Bool {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      return !trimmed.isEmpty && !presets.contains { !$0.isCustom && $0.name == trimmed }
    }

    func onToggleEnabled(_ enabled: Bool) {}
    func onLevelingStrengthChanged(_ strength: LevelingStrength) {}
    func onPreampChanged(_ value: Float) {}
    func onBandChanged(_ index: Int, gain: Float) {}
    func onPresetSelected(_ preset: Preset) {}
    func onSavePreset(named name: String) {}
    func onDeletePreset(_ preset: Preset) {}

    init(
      isPresented: Bool = false,
      isEnabled: Bool = false,
      levelingStrength: LevelingStrength = .off,
      preamp: Float = 0,
      bandGains: [Float] = [Float](repeating: 0, count: 7),
      bandLabels: [String] = ["60", "150", "400", "1K", "2.4K", "6K", "15K"],
      presets: [Preset] = []
    ) {
      self.isPresented = isPresented
      self.isEnabled = isEnabled
      self.levelingStrength = levelingStrength
      self.preamp = preamp
      self.bandGains = bandGains
      self.bandLabels = bandLabels
      self.presets = presets
    }
  }
}

extension EqualizerSheet.Model {
  static var mock: EqualizerSheet.Model {
    .init(
      isEnabled: true,
      levelingStrength: .medium,
      presets: EqualizerSheet.defaultPresets
    )
  }
}

extension EqualizerSheet {
  static let defaultPresets: [Preset] = [
    Preset(name: "Flat", preamp: 0, gains: [0, 0, 0, 0, 0, 0, 0]),
    Preset(name: "Bass Boost", preamp: 0, gains: [8, 4, 0, 0, 0, 0, 0]),
    Preset(name: "Treble Boost", preamp: 0, gains: [0, 0, 0, 0, 4, 6, 8]),
    Preset(name: "Spoken Word", preamp: 0, gains: [-4, 0, 2, 6, 4, 1, -2]),
    Preset(name: "Loudness", preamp: 0, gains: [6, 2, -2, 0, 4, 5, 6]),
    Preset(name: "High Speed 1", preamp: 0, gains: [4, 3, 2, 1, -2, -3, -4]),
    Preset(name: "High Speed 2", preamp: 0, gains: [-2, 0, -1, 3, 2, 0, -3]),
  ]
}

#Preview {
  EqualizerSheet(model: .mock)
}
