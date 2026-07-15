import SwiftUI

struct TimerPickerSheet: View {
  @Binding var model: Model

  var body: some View {
    Group {
      if case .none = model.current {
        pickerContent
      } else {
        runningContent
      }
    }
    .safeAreaInset(edge: .bottom) {
      if case .none = model.current {
        pickerFooter
      } else {
        runningFooter
      }
    }
  }

  @ViewBuilder
  private var pickerContent: some View {
    VStack(spacing: 24) {
      Picker("Mode", selection: selectedTab) {
        ForEach(Model.Tab.allCases) { tab in
          Text(tab.displayName).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .controlSize(.extraLarge)
      .padding(.horizontal, 20)
      .padding(.top, 30)

      if selectedTab.wrappedValue == .timer {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
          ForEach([15, 30, 45, 60], id: \.self) { minutes in
            quickTimerButton(for: minutes)
          }
        }
        .padding(.horizontal, 20)

        customTimeSection()

        endOfChapterSection()
      } else {
        alarmSection()
      }
    }
    .padding(.bottom, 24)
  }

  @ViewBuilder
  private var pickerFooter: some View {
    Button {
      if selectedTab.wrappedValue == .timer {
        model.onStartTimerTapped()
      } else {
        model.onAlarmStartTapped()
      }
    } label: {
      Text("Set").frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .disabled(startDisabled)
    .padding(.horizontal, 20)
    .padding(.bottom, 20)
  }

  private var startDisabled: Bool {
    if selectedTab.wrappedValue == .timer {
      return model.selected == .none
    }
    if case .duration(0) = model.selected { return true }
    return false
  }

  @ViewBuilder
  private var runningContent: some View {
    VStack(spacing: 16) {
      Image(systemName: runningIcon)
        .font(.system(size: 44))
        .foregroundStyle(.secondary)

      Text(runningTitle)
        .font(.title2)
        .fontWeight(.semibold)

      runningCountdown
    }
    .padding(.top, 40)
    .frame(maxWidth: .infinity)
  }

  private var canAddTime: Bool {
    switch model.current {
    case .preset, .custom: true
    case .chapters, .atTime, .duration, .none: false
    }
  }

  @ViewBuilder
  private func addTimeButton(for minutes: Int) -> some View {
    Button(action: { model.onAddTimeTapped(minutes) }) {
      Text(verbatim: "+\(Duration.seconds(minutes * 60).formatted(.units(allowed: [.minutes], width: .abbreviated)))")
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
  }

  @ViewBuilder
  private func chapterStepper(count: Int) -> some View {
    HStack(spacing: 12) {
      Button(action: { model.onRunningChaptersChanged(count - 1) }) {
        ZStack {
          Image(systemName: "plus")
            .hidden()

          Image(systemName: "minus")
            .frame(maxWidth: .infinity)
        }
      }
      .disabled(count < 2)

      Button(action: { model.onRunningChaptersChanged(count + 1) }) {
        Image(systemName: "plus")
          .frame(maxWidth: .infinity)
      }
      .disabled(count >= model.maxRemainingChapters)
    }
    .buttonStyle(.bordered)
  }

  private var runningIcon: String {
    if case .atTime = model.current { return "bell.fill" }
    return "timer"
  }

  private var runningTitle: LocalizedStringKey {
    if case .atTime = model.current { return "Alarm" }
    return "Sleep timer"
  }

  @ViewBuilder
  private var runningCountdown: some View {
    switch model.current {
    case .preset(let seconds), .custom(let seconds), .duration(let seconds):
      Text(Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond)))
        .font(.system(size: 40, weight: .bold, design: .monospaced))

    case .chapters(let count):
      Text(count == 1 ? "End of chapter" : "End of \(count) chapters")
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.horizontal, 20)
        .font(.system(size: 36, weight: .bold, design: .monospaced))

    case .atTime(let trigger):
      Text(
        timerInterval: min(Date(), trigger)...trigger,
        pauseTime: nil,
        countsDown: true,
        showsHours: true
      )
      .font(.system(size: 40, weight: .bold, design: .monospaced))

    case .none:
      EmptyView()
    }
  }

  @ViewBuilder
  private var runningFooter: some View {
    VStack(spacing: 12) {
      if canAddTime {
        HStack(spacing: 12) {
          ForEach([5, 10, 30], id: \.self) { minutes in
            addTimeButton(for: minutes)
          }
        }
      }

      if case .chapters(let count) = model.current {
        chapterStepper(count: count)
      }

      Button {
        if case .atTime = model.current {
          model.onAlarmOffTapped()
        } else {
          model.onOffSelected()
        }
      } label: {
        Text("Cancel").frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(.red)
    }
    .controlSize(.large)
    .padding(.horizontal, 20)
    .padding(.bottom, 20)
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

      if case .custom = model.selected {
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

  private func formatCustomTime(hours: Int, minutes: Int) -> String {
    if hours > 0 {
      "\(hours)hr \(minutes)min"
    } else {
      "\(minutes)min"
    }
  }

  private var selectedTab: Binding<Model.Tab> {
    Binding(
      get: { model.selected.isAlarm ? .alarm : .timer },
      set: { newValue in
        switch newValue {
        case .timer: model.selected = .none
        case .alarm: model.selected = .atTime(.now.advanced(by: 600))
        }
      }
    )
  }

  private var isDurationMode: Binding<Bool> {
    Binding(
      get: { if case .duration = model.selected { true } else { false } },
      set: { newValue in
        if newValue {
          let seconds = TimeInterval(model.customHours * 3600 + model.customMinutes * 60)
          model.selected = .duration(seconds)
        } else {
          model.selected = .atTime(.now.advanced(by: 600))
        }
      }
    )
  }

  private var alarmSelectedTime: Binding<Date> {
    Binding(
      get: {
        if case .atTime(let date) = model.selected { return date }
        return .now.advanced(by: 600)
      },
      set: { model.selected = .atTime($0) }
    )
  }

  @ViewBuilder
  private func alarmSection() -> some View {
    VStack(spacing: 20) {
      Picker("Alarm Type", selection: isDurationMode) {
        Text("At Time").tag(false)
        Text("In Duration").tag(true)
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 20)

      ZStack {
        if !isDurationMode.wrappedValue {
          DatePicker(
            "Alarm time",
            selection: alarmSelectedTime,
            displayedComponents: .hourAndMinute
          )
          .datePickerStyle(.wheel)
          .labelsHidden()
        } else {
          HStack(spacing: 20) {
            VStack(spacing: 8) {
              Picker("Hours", selection: $model.customHours) {
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
              Picker("Minutes", selection: $model.customMinutes) {
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
          .onChange(of: [model.customHours, model.customMinutes]) { _, new in
            model.selected = .duration(TimeInterval(new[0] * 3600 + new[1] * 60))
          }
        }
      }
      .frame(height: 210)
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
      case atTime(Date)
      case duration(TimeInterval)
      case none

      var isAlarm: Bool {
        switch self {
        case .atTime, .duration: true
        default: false
        }
      }
    }

    var isPresented: Bool = false
    var selected: Selection = .none
    var current: Selection = .none
    var customHours: Int = 0
    var customMinutes: Int = 1
    var maxRemainingChapters: Int = 0
    var completedAlert: TimerCompletedAlertView.Model?
    var estimatedEndTime: String?

    init() {}

    func onQuickTimerSelected(_ minutes: Int) {}
    func onAddTimeTapped(_ minutes: Int) {}
    func onChaptersChanged(_ value: Int) {}
    func onRunningChaptersChanged(_ value: Int) {}
    func onOffSelected() {}
    func onStartTimerTapped() {}
    func onAlarmStartTapped() {}
    func onAlarmOffTapped() {}
  }
}

extension TimerPickerSheet.Model {
  static let mock = TimerPickerSheet.Model()
}

#Preview {
  TimerPickerSheet(model: .constant(.mock))
}
