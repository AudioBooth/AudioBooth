import SwiftUI

struct TimerPickerSheet: View {
  @Binding var model: Model
  @State private var height: CGFloat = 200
  @State private var isCustomExpended: Bool = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        VStack(spacing: 24) {
          Text("Timer")
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .padding(.top, 20)

          LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
              quickTimerButton(for: minutes)
            }
          }
          .padding(.horizontal, 20)

          customTimeSection()

          endOfChapterSection()

          offButton()
        }
        .padding(.bottom, 40)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Start") {
              model.onStartTimerTapped()
            }
            .disabled(model.selected == .none)
            .tint(.primary)
          }
        }
      }
      .background {
        GeometryReader { proxy in
          Color.clear
            .onAppear { height = proxy.size.height }
            .onChange(of: proxy.size.height) { _, new in
              withAnimation { height = new }
            }
        }
      }
    }
    .presentationDetents([.height(height)])
    .presentationDragIndicator(.visible)
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
      Text(minutes == 60 ? "1 hr" : "\(minutes) min")
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(.primary)
        .padding(8)
        .frame(maxWidth: .infinity)
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected ? Color.accentColor : .primary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(Rectangle())
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
        .contentShape(Rectangle())
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
              .pickerStyle(WheelPickerStyle())
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
              .pickerStyle(WheelPickerStyle())

              Text(model.customMinutes == 1 ? "min" : "mins")
                .font(.system(size: 16))
                .foregroundColor(.primary)
            }
          }
          .padding(.horizontal, 10)
          .frame(height: 120)
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
      Button(action: { model.onChaptersChanged(1) }) {
        VStack(alignment: .leading, spacing: 2) {
          Text(chapterCount == 1 ? "End of chapter" : "End of \(chapterCount) chapters")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.primary)

          if chapterCount > 1 {
            Text("Includes your current chapter")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
            .contentShape(Circle())
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
            .contentShape(Circle())
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
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
    .padding(.horizontal, 20)
  }

  private func formatCustomTime(hours: Int, minutes: Int) -> String {
    if hours > 0 {
      "\(hours)hr \(minutes)min"
    } else {
      "\(minutes)min"
    }
  }
}

extension TimerPickerSheet {
  @Observable class Model {
    enum Selection: Equatable {
      case preset(TimeInterval)
      case custom(TimeInterval)
      case chapters(Int)
      case none
    }

    var isPresented: Bool = false
    var selected: Selection = .none
    var current: Selection = .none
    var customHours: Int = 0
    var customMinutes: Int = 1
    var maxRemainingChapters: Int = 0
    var completedAlert: TimerCompletedAlertView.Model?

    init() {}

    func onQuickTimerSelected(_ minutes: Int) {}
    func onChaptersChanged(_ value: Int) {}
    func onOffSelected() {}
    func onStartTimerTapped() {}
  }
}

extension TimerPickerSheet.Model {
  static let mock = TimerPickerSheet.Model()
}

#Preview {
  TimerPickerSheet(model: .constant(.mock))
}
