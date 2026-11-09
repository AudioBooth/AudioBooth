import Combine
import SwiftUI

struct TimerPickerSheet: View {
  @ObservedObject var model: Model

  @FocusState private var focusedUnit: Unit?

  private let minuteOptions = Array(stride(from: 5, through: 180, by: 5))

  var body: some View {
    VStack(spacing: 4) {
      header

      if let status = model.status {
        runningContent(status)
      } else {
        pickerContent
      }
    }
    .navigationTitle("Sleep Timer")
    .navigationBarTitleDisplayMode(.inline)
    .defaultFocus($focusedUnit, model.selectedUnit)
    .onChange(of: focusedUnit) { _, unit in
      if let unit {
        model.selectedUnit = unit
      }
    }
    .onAppear(perform: model.onAppear)
  }

  @ViewBuilder
  private var header: some View {
    if let errorMessage = model.errorMessage {
      Text(errorMessage)
        .font(.footnote)
        .foregroundStyle(.secondary)
    } else if model.status == nil, let estimatedEnd = model.estimatedEnd {
      Text(estimatedEnd)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
  }

  private func runningContent(_ status: String) -> some View {
    VStack {
      Spacer()

      Text(status)
        .font(.title3)
        .monospacedDigit()
        .multilineTextAlignment(.center)

      Spacer()

      Button(action: model.onCancelTapped) {
        Label("Turn Off", systemImage: "xmark")
          .opacity(model.isLoading ? 0 : 1)
          .overlay {
            if model.isLoading {
              ProgressView()
                .controlSize(.small)
            }
          }
      }
      .disabled(model.isLoading)
    }
  }

  private var pickerContent: some View {
    VStack(spacing: 4) {
      HStack(spacing: 8) {
        wheel(title: "Minutes", unit: .minutes, selection: $model.customMinutes, values: minuteOptions)

        if model.hasChapters {
          wheel(
            title: "Chapters",
            unit: .chapters,
            selection: $model.customChapters,
            values: Array(1...model.maxChapters)
          )
        }
      }

      Button(action: model.onStartTapped) {
        Text("Start")
          .opacity(model.isLoading ? 0 : 1)
          .overlay {
            if model.isLoading {
              ProgressView()
                .controlSize(.small)
            }
          }
      }
      .disabled(model.isLoading)
    }
  }

  private func wheel(
    title: LocalizedStringKey,
    unit: Unit,
    selection: Binding<Int>,
    values: [Int]
  ) -> some View {
    VStack(spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(model.selectedUnit == unit ? .primary : .secondary)

      Picker(title, selection: selection) {
        ForEach(values, id: \.self) { value in
          Text(verbatim: value.formatted()).tag(value)
        }
      }
      .pickerStyle(.wheel)
      .labelsHidden()
      .focused($focusedUnit, equals: unit)
    }
  }
}

extension TimerPickerSheet {
  enum Selection {
    case none
    case duration(TimeInterval)
    case chapters(Int)
    case endsAt(Date)
  }

  enum Unit {
    case minutes
    case chapters
  }

  @Observable
  class Model: ObservableObject {
    var isPresented: Bool = false
    var current: Selection = .none
    var isLoading: Bool = false
    var errorMessage: String?
    var selectedUnit: Unit = .minutes
    var customMinutes: Int = 30
    var customChapters: Int = 1
    var chapterEstimates: [TimeInterval] = [] {
      didSet {
        customChapters = min(customChapters, maxChapters)
      }
    }

    var hasChapters: Bool {
      !chapterEstimates.isEmpty
    }

    var maxChapters: Int {
      max(1, chapterEstimates.count)
    }

    var status: String? {
      switch current {
      case .none:
        return nil
      case .duration(let remaining):
        return Duration.seconds(remaining).formatted(.time(pattern: .hourMinuteSecond))
      case .chapters(1):
        return String(localized: "End of chapter")
      case .chapters(let count):
        return String(localized: "\(count) chapters")
      case .endsAt(let date):
        return pausesText(at: date)
      }
    }

    var estimatedEnd: String? {
      let seconds: TimeInterval
      switch selectedUnit {
      case .minutes:
        seconds = TimeInterval(customMinutes * 60)
      case .chapters:
        guard chapterEstimates.indices.contains(customChapters - 1) else { return nil }
        seconds = chapterEstimates[customChapters - 1]
      }

      return pausesText(at: Date().addingTimeInterval(seconds))
    }

    private func pausesText(at date: Date) -> String {
      let time = date.formatted(date: .omitted, time: .shortened)
      return String(localized: "Pauses at \(time)")
    }

    func onAppear() {}
    func onMinutesSelected(_ minutes: Int) {}
    func onChaptersSelected(_ count: Int) {}
    func onCancelTapped() {}

    func onStartTapped() {
      switch selectedUnit {
      case .minutes:
        onMinutesSelected(customMinutes)
      case .chapters:
        onChaptersSelected(customChapters)
      }
    }
  }
}

#Preview {
  NavigationStack {
    TimerPickerSheet(model: TimerPickerSheet.Model())
  }
}
