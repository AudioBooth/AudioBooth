import SwiftUI

struct SkipRewindPreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject private var preferences = UserPreferences.shared

  private let skipPresets: [Double] = [10, 15, 30, 60, 90]
  private let pauseTicks: [Double] = [0, 1, 2, 5, 10, 30, 60, 120, 300, 600, 1800, 3600]
  private let rewindBounds: ClosedRange<Double> = 0...90
  private let interruptionOptions: [Double] = [0, 5, 10, 15, 30, 45, 60, 75, 90]

  @State private var rewindMin: Double = UserPreferences.shared.smartRewindInterval
  @State private var rewindMax: Double = UserPreferences.shared.smartRewindMaxInterval
  @State private var pauseThreshold: Double = UserPreferences.shared.smartRewindAfterPauseThreshold

  private var autoRewindEnabled: Binding<Bool> {
    Binding(
      get: { preferences.smartRewindMaxInterval > 0 || preferences.smartRewindInterval > 0 },
      set: { isOn in
        if isOn {
          preferences.smartRewindInterval = preferences.smartRewindInterval > 0 ? preferences.smartRewindInterval : 6
          preferences.smartRewindMaxInterval =
            preferences.smartRewindMaxInterval > 0 ? preferences.smartRewindMaxInterval : 30
        } else {
          preferences.smartRewindInterval = 0
          preferences.smartRewindMaxInterval = 0
        }
      }
    )
  }

  var body: some View {
    Form {
      Section {
        SkipPresetCard(
          backInterval: $preferences.skipBackwardInterval,
          forwardInterval: $preferences.skipForwardInterval,
          presets: skipPresets
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Skip Forward & Back")
      }

      Section {
        Toggle(isOn: autoRewindEnabled) {
          PreferenceRow(
            systemImage: "gobackward",
            tint: .blue,
            title: "Auto-rewind on Resume",
            subtitle: autoRewindSubtitle
          )
        }
        .listRowBackground(theme.colors.background.card)

        if autoRewindEnabled.wrappedValue {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("Rewind Range")
                .font(.subheadline)
                .fontWeight(.medium)
              Spacer()
              Text(rangeLabel)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
            }
            RangeSlider(
              low: $rewindMin,
              high: $rewindMax,
              bounds: rewindBounds
            )
          }
          .listRowBackground(theme.colors.background.card)

          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("Rewind After Paused For")
                .font(.subheadline)
                .fontWeight(.medium)
              Spacer()
              Text(thresholdLabel(pauseThreshold) + "+")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
            }
            TickSlider(value: $pauseThreshold, ticks: pauseTicks)
            Text("Only rewinds if paused for \(thresholdLabel(pauseThreshold))+")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .listRowBackground(theme.colors.background.card)

          Toggle(isOn: $preferences.smartRewindChapterBarrier) {
            PreferenceRow(
              systemImage: "rectangle.split.2x1",
              tint: .purple,
              title: "Chapter Barrier",
              subtitle: "Don't rewind past the start of the current chapter"
            )
          }
          .listRowBackground(theme.colors.background.card)

          Toggle(isOn: $preferences.smartRewindOnSessionStart) {
            PreferenceRow(
              systemImage: "play",
              tint: .green,
              title: "Rewind on Session Start",
              subtitle: "Rewind \(Int(rewindMax))s when starting a new session"
            )
          }
          .listRowBackground(theme.colors.background.card)

          RewindPreviewCard(
            minInterval: rewindMin,
            maxInterval: rewindMax,
            threshold: pauseThreshold
          )
          .listRowInsets(EdgeInsets())
          .listRowBackground(theme.colors.background.card)
        }
      } header: {
        Text("Smart Rewind")
      } footer: {
        Text(
          "Rewind a small amount after a brief pause and more after long ones, scaling with how long you've been away."
        )
        .font(.caption)
      }

      Section {
        Picker(selection: $preferences.smartRewindOnInterruptionInterval) {
          ForEach(interruptionOptions, id: \.self) { value in
            Text(secondsLabel(value)).tag(value)
          }
        } label: {
          PreferenceRow(
            systemImage: "phone",
            tint: .pink,
            title: "On Interruption",
            subtitle: "Calls, alarms, other audio"
          )
        }
        .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Audio Interruptions")
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .navigationTitle("Skip & Rewind")
    .onDisappear {
      preferences.smartRewindInterval = rewindMin
      preferences.smartRewindMaxInterval = rewindMax
      preferences.smartRewindAfterPauseThreshold = pauseThreshold
    }
  }

  private var autoRewindSubtitle: String {
    if !autoRewindEnabled.wrappedValue {
      return String(localized: "Off")
    }
    return String(
      localized: "On - \(Int(rewindMin))s to \(Int(rewindMax))s based on pause length"
    )
  }

  private var rangeLabel: String {
    "\(Int(rewindMin))s – \(Int(rewindMax))s"
  }

  private func thresholdLabel(_ value: Double) -> String {
    if value < 60 { return "\(Int(value))s" }
    if value < 3600 { return "\(Int(value / 60)) min" }
    return "\(Int(value / 3600)) hr"
  }

  private func secondsLabel(_ value: Double) -> String {
    if value == 0 { return String(localized: "Off") }
    return Duration.seconds(value).formatted(.units(allowed: [.seconds], width: .abbreviated))
  }
}

private struct SkipPresetCard: View {
  @Binding var backInterval: Double
  @Binding var forwardInterval: Double
  let presets: [Double]

  var body: some View {
    VStack(spacing: 20) {
      HStack {
        skipBadge(
          systemImage: "\(Int(backInterval)).arrow.trianglehead.counterclockwise",
          label: "Back"
        )
        Spacer()
        skipBadge(
          systemImage: "\(Int(forwardInterval)).arrow.trianglehead.clockwise",
          label: "Forward"
        )
      }

      VStack(spacing: 10) {
        chipRow(label: "Back", selection: $backInterval)
        chipRow(label: "Forward", selection: $forwardInterval)
      }
    }
    .padding(16)
  }

  private func skipBadge(systemImage: String, label: LocalizedStringKey) -> some View {
    VStack(spacing: 6) {
      Circle()
        .fill(Color.accentColor.opacity(0.15))
        .frame(width: 64, height: 64)
        .overlay(
          Image(systemName: systemImage)
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(Color.accentColor)
        )
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func chipRow(label: LocalizedStringKey, selection: Binding<Double>) -> some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .frame(width: 56, alignment: .leading)

      HStack(spacing: 6) {
        ForEach(presets, id: \.self) { value in
          presetChip(value, selection: selection)
        }
      }
    }
  }

  private func presetChip(_ value: Double, selection: Binding<Double>) -> some View {
    let isSelected = abs(selection.wrappedValue - value) < 0.1
    return Button {
      selection.wrappedValue = value
    } label: {
      Text("\(Int(value))s")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.black : Color.gray.opacity(0.12))
        )
    }
    .buttonStyle(.plain)
  }
}

private struct RangeSlider: View {
  @Binding var low: Double
  @Binding var high: Double
  let bounds: ClosedRange<Double>

  private let trackHeight: CGFloat = 4
  private let thumbSize: CGFloat = 24

  var body: some View {
    GeometryReader { geo in
      let usable = max(geo.size.width - thumbSize, 1)
      let lowX = position(for: low, in: usable)
      let highX = position(for: high, in: usable)

      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.gray.opacity(0.2))
          .frame(height: trackHeight)
          .padding(.horizontal, thumbSize / 2)

        Capsule()
          .fill(Color.accentColor)
          .frame(width: max(highX - lowX, 0), height: trackHeight)
          .offset(x: lowX + thumbSize / 2)

        thumb
          .offset(x: lowX)
          .gesture(dragGesture(for: .low, usable: usable))

        thumb
          .offset(x: highX)
          .gesture(dragGesture(for: .high, usable: usable))
      }
      .frame(height: thumbSize)
    }
    .frame(height: thumbSize)
  }

  private var thumb: some View {
    Circle()
      .fill(Color.white)
      .frame(width: thumbSize, height: thumbSize)
      .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
      .overlay(
        Circle().stroke(Color.accentColor, lineWidth: 2)
      )
  }

  private enum Thumb { case low, high }

  private func position(for value: Double, in usable: CGFloat) -> CGFloat {
    let span = bounds.upperBound - bounds.lowerBound
    let ratio = (value - bounds.lowerBound) / span
    return CGFloat(ratio) * usable
  }

  private func value(for x: CGFloat, in usable: CGFloat) -> Double {
    let clamped = min(max(x, 0), usable)
    let ratio = clamped / usable
    let raw = Double(ratio) * (bounds.upperBound - bounds.lowerBound) + bounds.lowerBound
    return raw.rounded()
  }

  private func dragGesture(for thumb: Thumb, usable: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { gesture in
        let v = value(for: gesture.location.x, in: usable)
        switch thumb {
        case .low:
          let newLow = min(v, high - 1)
          if newLow != low { low = newLow }
        case .high:
          let newHigh = max(v, low + 1)
          if newHigh != high { high = newHigh }
        }
      }
  }
}

private struct RewindPreviewCard: View {
  let minInterval: Double
  let maxInterval: Double
  let threshold: Double

  private static let baseSamples: [Double] = [30, 120, 600, 1800, 3600]

  private var samples: [Double] {
    var values = Set(Self.baseSamples)
    values.insert(threshold)
    return values.sorted()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Preview")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)

      ForEach(samples.filter { $0 >= threshold }, id: \.self) { seconds in
        HStack {
          Text(pauseLabel(seconds))
          Spacer()
          Text("→ \(rewind(for: seconds), specifier: "%.1f")s rewind")
            .fontWeight(.semibold)
            .foregroundStyle(Color.accentColor)
        }
        .font(.caption2)
      }
    }
    .padding(16)
  }

  private func rewind(for pauseSeconds: Double) -> Double {
    if pauseSeconds < threshold { return 0 }
    let ceiling = max(samples.last ?? 3600, threshold + 1)
    let span = max(ceiling - threshold, 1)
    let progress = min(max((pauseSeconds - threshold) / span, 0), 1)
    return minInterval + progress * (maxInterval - minInterval)
  }

  private func pauseLabel(_ seconds: Double) -> String {
    if seconds < 60 { return String(localized: "\(Int(seconds))s pause") }
    if seconds < 3600 { return String(localized: "\(Int(seconds / 60)) min pause") }
    return String(localized: "\(Int(seconds / 3600)) hr pause")
  }
}

#Preview {
  NavigationStack {
    SkipRewindPreferencesView()
  }
}
