import SwiftUI

struct TimerPickerSheet: View {
  @Binding var model: Model
  @State private var isCustomExpended: Bool = false

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 24) {
        Text(model.selectedTab == .timer ? "Timer" : "Alarm")
          .font(.title2)
          .fontWeight(.semibold)
          .foregroundColor(.primary)
          .padding(.top, 50)

        Picker("Mode", selection: $model.selectedTab) {
          ForEach(Model.Tab.allCases) { tab in
            Text(tab.displayName).tag(tab)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)

        if model.selectedTab == .timer {
          LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
              quickTimerButton(for: minutes)
            }
          }
          .padding(.horizontal, 20)

          customTimeSection()

          endOfChapterSection()

          offButton()
        } else {
          alarmSection()
        }
      }
      .padding(.bottom, 40)
    }
    .overlay(alignment: .topTrailing) {
      if model.selectedTab == .timer {
        Button("Start") {
          model.onStartTimerTapped()
        }
        .buttonStyle(.bordered)
        .disabled(model.selected == .none)
        .tint(.primary)
        .padding()
      }
    }
  }

  @ViewBuilder
  func quickTimerButton(for minutes: Int) -> some View {
    let isSelected = {
      if case .preset(let selectedSeconds) = model.selected {
        return selectedSeconds == TimeInterval(minutes * 60)
      }
      return false
    }()

    Button(action: { model.onQuickTimerSelected(minutes) }) {
      Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(.primary)
        .padding(8)
        .frame(maxWidth: .infinity)
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected ? Color.accentColor : .primary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        }
        .interactiveTarget()
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  func customTimeSection() -> some View {
    let isSelected = {
      if case .custom = model.selected {
        return true
      }
      return false
    }()

    VStack(spacing: 0) {
      Button(action: {
        isCustomExpended = true
        model.selected = .custom(TimeInterval(model.customHours * 3600 + model.customMinutes * 60))
      }) {
        HStack {
          Text("Custom time")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.primary)
          Spacer()
          Text(formatCustomTime(hours: model.customHours, minutes: model.customMinutes))
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .interactiveTarget()
      }
      .buttonStyle(.plain)

      if isCustomExpended {
        VStack(spacing: 16) {
          HStack {
            HStack {
              Picker("Hours", selection: $model.customHours) {
                ForEach(0..<24, id: \.self) { i in
                  Text("\(i)").tag(i)
                }
              }
              #if os(iOS) && !targetEnvironment(macCatalyst)
              .pickerStyle(.wheel)
              #else
              .pickerStyle(.menu)
              #endif
              .onChange(of: model.customHours) { oldValue, newValue in
                if oldValue == 0 && newValue > 0 && model.customMinutes == 0 {
                  model.customMinutes = 1
                } else if oldValue > 0 && newValue == 0 && model.customMinutes == 0 {
                  model.customMinutes = 1
                }
              }

              Text(model.customHours == 1 ? "hour" : "hours")
                .font(.system(size: 16))
                .foregroundColor(.primary)
            }

            HStack {
              Picker("Minutes", selection: $model.customMinutes) {
                let range = model.customHours > 0 ? 0..<60 : 1..<60
                ForEach(range, id: \.self) { i in
                  Text("\(i)").tag(i)
                }
              }
              #if os(iOS) && !targetEnvironment(macCatalyst)
              .pickerStyle(.wheel)
              #else
              .pickerStyle(.menu)
              #endif

              Text(model.customMinutes == 1 ? "min" : "mins")
                .font(.system(size: 16))
                .foregroundColor(.primary)
            }
          }
          .padding(.horizontal, 10)
          #if os(iOS) && !targetEnvironment(macCatalyst)
          .frame(height: 120)
          #endif
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(isSelected ? Color.accentColor : .primary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
    }
    .padding(.horizontal, 20)
    .animation(.easeInOut(duration: 0.3), value: isSelected)
    .onChange(of: [model.customHours, model.customMinutes]) { old, new in
      if old[0] == 0, old[1] == 1, new[1] == 1 {
        model.customMinutes = 0
      }
      model.selected = .custom(TimeInterval(new[0] * 3600 + new[1] * 60))
    }
  }

  @ViewBuilder
  func endOfChapterSection() -> some View {
    let (isSelected, chapterCount) = {
      if case .chapters(let count) = model.selected {
        return (true, count)
      }
      return (false, 1)
    }()

    HStack {
      Button(action: {
        model.onChaptersChanged(chapterCount)
        model.onStartTimerTapped()
      }) {
        VStack(alignment: .leading, spacing: 2) {
          Text(chapterCount == 1 ? "End of chapter" : "End of \(chapterCount) chapters")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.primary)

          if isSelected, let estimatedEndTime = model.estimatedEndTime {
            Text(estimatedEndTime)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .interactiveTarget()
      }

      HStack(spacing: 16) {
        Button(action: { model.onChaptersChanged(chapterCount - 1) }) {
          Circle()
            .stroke(Color.primary.opacity(0.3), lineWidth: 2)
            .frame(width: 32, height: 32)
            .overlay {
              Image(systemName: "minus")
                .font(.caption)
                .foregroundColor(.primary)
            }
            .interactiveTarget()
        }
        .disabled(chapterCount < 2)

        Button(action: { model.onChaptersChanged(chapterCount + 1) }) {
          Circle()
            .stroke(Color.primary.opacity(0.3), lineWidth: 2)
            .frame(width: 32, height: 32)
            .overlay {
              Image(systemName: "plus")
                .font(.caption)
                .foregroundColor(.primary)
            }
            .interactiveTarget()
        }
        .disabled(chapterCount >= model.maxRemainingChapters)
      }
    }
    .buttonStyle(.plain)
    .padding(8)
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.clear)
        .stroke(isSelected ? Color.accentColor : .primary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
    }
    .padding(.horizontal, 20)
  }

  @ViewBuilder
  func offButton() -> some View {
    Button(action: model.onOffSelected) {
      RoundedRectangle(cornerRadius: 8)
        .stroke(
          {
            if case .none = model.selected {
              return Color.accentColor
            }
            return .primary.opacity(0.3)
          }(),
          lineWidth: {
            if case .none = model.selected {
              return 2
            }
            return 1
          }()
        )
        .frame(height: 44)
        .overlay {
          Text("Off")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.primary)
        }
        .interactiveTarget()
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 20)
  }

  private func formatCustomTime(hours: Int, minutes: Int) -> String {
    if hours > 0 {
      "\(hours)hr \(minutes)min"
    } else {
      "\(minutes)min"
    }
  }

  @ViewBuilder
  private func alarmSection() -> some View {
    VStack(spacing: 20) {
      Picker("Alarm Type", selection: $model.alarmMode) {
        ForEach(Model.AlarmMode.allCases) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 20)

      ZStack {
        if model.alarmMode == .atTime {
          DatePicker(
            "Alarm time",
            selection: $model.alarmSelectedTime,
            displayedComponents: .hourAndMinute
          )
          .datePickerStyle(.wheel)
          .labelsHidden()
        } else {
          HStack(spacing: 20) {
            VStack(spacing: 8) {
              Picker("Hours", selection: $model.alarmDurationHours) {
                ForEach(0..<24, id: \.self) { value in
                  Text("\(value)").tag(value)
                }
              }
              .pickerStyle(.wheel)
              .frame(maxWidth: .infinity)

              Text("Hours")
                .font(.caption)
                .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
              Picker("Minutes", selection: $model.alarmDurationMinutes) {
                ForEach(0..<60, id: \.self) { value in
                  Text("\(value)").tag(value)
                }
              }
              .pickerStyle(.wheel)
              .frame(maxWidth: .infinity)

              Text("Minutes")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          .padding(.horizontal, 20)
        }
      }
      .frame(height: 210)

      if model.alarmCurrent != nil {
        VStack(spacing: 14) {
          if let alarm = model.alarmCurrent, !model.isAlarmRinging {
            Text(
              timerInterval: Date()...alarm.nextTrigger,
              pauseTime: nil,
              countsDown: true,
              showsHours: true
            )
            .font(.system(size: 34, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .center)
          } else {
            Text("00:00:00")
              .font(.system(size: 34, weight: .bold, design: .monospaced))
              .monospacedDigit()
              .frame(maxWidth: .infinity, alignment: .center)
          }

          VStack(spacing: 6) {
            HStack {
              Text("Add Time")
                .font(.subheadline)
                .fontWeight(.semibold)
              Spacer()
              Text("\(model.alarmAddTimeMinutes) min")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Slider(
              value: Binding(
                get: { Double(model.alarmAddTimeMinutes) },
                set: { model.onAlarmAddTimeMinutesChanged(Int($0.rounded())) }
              ),
              in: 1...30,
              step: 1
            )
          }

          HStack(alignment: .center, spacing: 10) {
            let alarmStopTitle = model.isAlarmRinging ? "Stop" : "Cancel"

            Button("Add Time") {
              model.onAlarmAddTimeTapped()
            }
            .buttonStyle(.borderedProminent)
            .tint(.gray)

            Button(alarmStopTitle) {
              model.onAlarmOffTapped()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
          }
          .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
      } else {
        Button("Set Alarm") {
          model.onAlarmStartTapped()
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .padding(.horizontal, 20)
      }
    }
  }
}

extension TimerPickerSheet {
  @Observable class Model {
    enum Tab: String, CaseIterable, Identifiable {
      case timer
      case alarm

      var id: String { rawValue }

      var displayName: String {
        switch self {
        case .timer: "Timer"
        case .alarm: "Alarm"
        }
      }
    }

    enum Selection: Equatable {
      case preset(TimeInterval)
      case custom(TimeInterval)
      case chapters(Int)
      case none
    }

    enum AlarmMode: String, CaseIterable, Identifiable {
      case atTime
      case duration

      var id: String { rawValue }

      var displayName: String {
        switch self {
        case .atTime: "At Time"
        case .duration: "In Duration"
        }
      }
    }

    struct AlarmState: Equatable {
      var nextTrigger: Date
    }

    var isPresented: Bool = false
    var selectedTab: Tab = .timer
    var selected: Selection = .none
    var current: Selection = .none
    var customHours: Int = 0
    var customMinutes: Int = 1
    var maxRemainingChapters: Int = 0
    var completedAlert: TimerCompletedAlertView.Model?
    var estimatedEndTime: String?
    var alarmMode: AlarmMode = .atTime
    var alarmSelectedTime: Date = .now
    var alarmDurationHours: Int = 0
    var alarmDurationMinutes: Int = 15
    var alarmAddTimeMinutes: Int = 5
    var alarmCountdownText: String = "00:00:00"
    var alarmCurrent: AlarmState?
    var isAlarmRinging: Bool = false
    var isAlarmActive: Bool { alarmCurrent != nil }

    init() {}

    func onQuickTimerSelected(_ minutes: Int) {}
    func onChaptersChanged(_ value: Int) {}
    func onOffSelected() {}
    func onStartTimerTapped() {}
    func onAlarmStartTapped() {}
    func onAlarmOffTapped() {}
    func onAlarmAddTimeTapped() {}
    func onAlarmAddTimeMinutesChanged(_ value: Int) {}
  }
}

extension TimerPickerSheet.Model {
  static let mock = TimerPickerSheet.Model()
}

#Preview {
  TimerPickerSheet(model: .constant(.mock))
}
