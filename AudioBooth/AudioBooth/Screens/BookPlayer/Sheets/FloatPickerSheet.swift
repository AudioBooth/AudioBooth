import Combine
import SwiftUI

struct FloatPickerSheet: View {
  @Binding var model: Model

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 24) {
        Text(model.title)
          .font(.title2)
          .fontWeight(.semibold)
          .foregroundColor(.primary)
          .padding(.top, 50)

        Text(verbatim: "\(String(format: "%.2f", model.value))×")
          .font(.largeTitle)
          .fontWeight(.medium)
          .foregroundColor(.primary)

        HStack(spacing: 12) {
          Button(action: { model.onDecrease() }) {
            Circle()
              .stroke(Color.primary.opacity(0.3), lineWidth: 2)
              .frame(width: 40, height: 40)
              .overlay {
                Image(systemName: "minus")
                  .font(.title2)
                  .foregroundColor(.primary)
              }
          }
          .disabled(model.value <= model.range.lowerBound)

          Slider(
            value: Binding(
              get: { model.value },
              set: { model.onValueChanged($0) }
            ),
            in: model.range,
            step: model.step
          )

          Button(action: { model.onIncrease() }) {
            Circle()
              .stroke(Color.primary.opacity(0.3), lineWidth: 2)
              .frame(width: 40, height: 40)
              .overlay {
                Image(systemName: "plus")
                  .font(.title2)
                  .foregroundColor(.primary)
              }
          }
          .disabled(model.value >= model.range.upperBound)
        }
        .padding(.horizontal, 40)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
          ForEach(model.presets, id: \.self) { preset in
            presetButton(for: preset)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
      }
      .padding(.bottom, 40)
    }
  }

  @ViewBuilder
  private func presetButton(for preset: Double) -> some View {
    let isSelected = (model.value / model.step).rounded() == (preset / model.step).rounded()
    Button(action: {
      model.onValueChanged(preset)
      model.isPresented = false
    }) {
      RoundedRectangle(cornerRadius: 8)
        .stroke(isSelected ? Color.accentColor : .primary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        .frame(height: 44)
        .overlay {
          VStack(spacing: 2) {
            Text(String(format: "%.2f", preset))
              .font(.system(size: 16, weight: .medium))
              .foregroundColor(.primary)

            if preset == model.defaultValue {
              Text("DEFAULT")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
            }
          }
        }
    }
    .buttonStyle(.plain)
  }
}

extension FloatPickerSheet {
  @Observable
  class Model: ObservableObject {
    var title: String
    var value: Double
    var isPresented: Bool
    let range: ClosedRange<Double>
    let step: Double
    let presets: [Double]
    let defaultValue: Double

    init(
      title: String = "",
      value: Double = 1.0,
      range: ClosedRange<Double> = 0.5...3.5,
      step: Double = 0.05,
      presets: [Double] = [0.7, 1.0, 1.2, 1.5, 1.7, 2.0],
      defaultValue: Double = 1.0,
      isPresented: Bool = false
    ) {
      self.title = title
      self.value = value
      self.range = range
      self.step = step
      self.presets = presets
      self.defaultValue = defaultValue
      self.isPresented = isPresented
    }

    func onIncrease() {}
    func onDecrease() {}
    func onValueChanged(_ value: Double) {}
  }
}

extension FloatPickerSheet.Model {
  static var mock: FloatPickerSheet.Model {
    .init(
      title: "Speed",
      value: 1.0,
      range: 0.5...3.5,
      step: 0.05,
      presets: [0.7, 1.0, 1.2, 1.5, 1.7, 2.0],
      defaultValue: 1.0
    )
  }
}

#Preview {
  FloatPickerSheet(model: .constant(.mock))
}
