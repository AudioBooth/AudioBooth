import SwiftUI

struct AlarmPickerSheet: View {
  @Binding var model: Model

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 24) {
        Text("Alarm")
          .font(.title2)
          .fontWeight(.semibold)
          .padding(.top, 40)

        Picker("Mode", selection: $model.mode) {
          ForEach(Model.Mode.allCases) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)

        modeContentSection

        if model.current != nil {
          VStack(spacing: 14) {
            Text(model.countdownText)
              .font(.system(size: 34, weight: .bold, design: .monospaced))
              .monospacedDigit()
              .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 6) {
              HStack {
                Text("Add Time")
                  .font(.subheadline)
                  .fontWeight(.semibold)
                Spacer()
                Text("\(model.addTimeMinutes) min")
                  .font(.subheadline)
                  .foregroundColor(.secondary)
              }

              Slider(
                value: Binding(
                  get: { Double(model.addTimeMinutes) },
                  set: { model.onAddTimeMinutesChanged(Int($0.rounded())) }
                ),
                in: 1...30,
                step: 1
              )
            }

            HStack(alignment: .center, spacing: 10) {
              let cancelButtonTitle = model.countdownText == "00:00:00" ? "Stop" : "Cancel"

              Button("Add Time") {
                model.onAddTimeTapped()
              }
              .buttonStyle(.borderedProminent)
              .tint(.gray)

              Button(cancelButtonTitle) {
                model.onOffSelected()
              }
              .buttonStyle(.borderedProminent)
              .tint(.red)
            }
            .frame(maxWidth: .infinity)
          }
          .padding(.horizontal, 20)
        } else {
          Button("Set Alarm") {
            model.onStartTapped()
          }
          .buttonStyle(.borderedProminent)
          .tint(.blue)
          .padding(.horizontal, 20)
        }
      }
      .padding(.bottom, 32)
    }
  }

  @ViewBuilder
  private var modeContentSection: some View {
    ZStack {
      if model.mode == .atTime {
        DatePicker(
          "Alarm time",
          selection: $model.selectedTime,
          displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.wheel)
        .labelsHidden()
      } else {
        durationPickerSection
      }
    }
    .frame(height: 210)
  }

  private var durationPickerSection: some View {
    HStack(spacing: 20) {
      VStack(spacing: 8) {
        Picker("Hours", selection: $model.durationHours) {
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
        Picker("Minutes", selection: $model.durationMinutes) {
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

extension AlarmPickerSheet {
  @Observable class Model {
    enum Mode: String, CaseIterable, Identifiable {
      case atTime
      case duration

      var id: String { rawValue }

      var displayName: String {
        switch self {
        case .atTime:
          return "At Time"
        case .duration:
          return "In Duration"
        }
      }
    }

    struct ActiveAlarm: Equatable {
      var nextTrigger: Date
    }

    var isPresented: Bool = false
    var mode: Mode = .atTime
    var selectedTime: Date = .now
    var durationHours: Int = 0
    var durationMinutes: Int = 15
    var addTimeMinutes: Int = 5
    var countdownText: String = "00:00:00"
    var current: ActiveAlarm?

    init() {}

    func onStartTapped() {}
    func onOffSelected() {}
    func onAddTimeTapped() {}
    func onAddTimeMinutesChanged(_ value: Int) {}
  }
}

extension AlarmPickerSheet.Model {
  static let mock = AlarmPickerSheet.Model()
}

#Preview {
  AlarmPickerSheet(model: .constant(.mock))
}
