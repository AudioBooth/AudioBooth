import Combine
import SwiftUI

struct EqualizerSheet: View {
  @ObservedObject var model: Model

  var body: some View {
    VStack(spacing: 0) {
      Text("Equalizer")
        .font(.title2)
        .fontWeight(.semibold)
        .foregroundColor(.primary)
        .padding(.top, 50)

      preampView
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .disabled(!model.isEnabled)

      bandsView
        .padding(.top, 24)

      presetsView
        .padding(.top, 20)
        .padding(.horizontal, 16)
        .padding(.bottom, 40)
    }
    .opacity(model.isEnabled ? 1 : 0.5)
    .overlay(alignment: .topTrailing) {
      Toggle(
        "",
        isOn: Binding(
          get: { model.isEnabled },
          set: { model.onToggleEnabled($0) }
        )
      )
      .labelsHidden()
      .padding()
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
    .disabled(!model.isEnabled)
  }

  private var presetsView: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Presets")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundColor(.primary)

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
        }
      }
    }
    .disabled(!model.isEnabled)
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
  struct Preset: Identifiable {
    let name: String
    let gains: [Float]
    var id: String { name }
  }

  @Observable
  class Model: ObservableObject {
    var isPresented: Bool
    var isEnabled: Bool
    var preamp: Float
    var bandGains: [Float]
    var bandLabels: [String]
    var presets: [Preset]

    var selectedPreset: String? {
      presets.first(where: { $0.gains == bandGains })?.name
    }

    func onToggleEnabled(_ enabled: Bool) {}
    func onPreampChanged(_ value: Float) {}
    func onBandChanged(_ index: Int, gain: Float) {}
    func onPresetSelected(_ preset: Preset) {}

    init(
      isPresented: Bool = false,
      isEnabled: Bool = false,
      preamp: Float = 0,
      bandGains: [Float] = [Float](repeating: 0, count: 6),
      bandLabels: [String] = ["60", "150", "400", "1K", "2.4K", "15K"],
      presets: [Preset] = []
    ) {
      self.isPresented = isPresented
      self.isEnabled = isEnabled
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
      presets: EqualizerSheet.defaultPresets
    )
  }
}

extension EqualizerSheet {
  static let defaultPresets: [Preset] = [
    Preset(name: "Flat", gains: [0, 0, 0, 0, 0, 0]),
    Preset(name: "Bass Boost", gains: [8, 4, 0, 0, 0, 0]),
    Preset(name: "Treble Boost", gains: [0, 0, 0, 0, 4, 8]),
    Preset(name: "Vocal", gains: [-2, 0, 2, 4, 3, -1]),
    Preset(name: "Spoken Word", gains: [-4, 0, 2, 6, 4, -2]),
    Preset(name: "Loudness", gains: [6, 2, -2, 0, 4, 6]),
  ]
}

#Preview {
  EqualizerSheet(model: .mock)
}
