import Combine
import SwiftUI

struct FloatPickerSheet: View {
  @Binding var model: Model

  private var editingValue: Double? {
    guard let index = model.editingPresetIndex,
      model.presets.indices.contains(index)
    else { return nil }
    return model.presets[index]
  }

  private var displayValue: Double {
    editingValue ?? model.value
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 24) {
        Text(model.title)
          .font(.title2)
          .fontWeight(.semibold)
          .foregroundColor(.primary)
          .padding(.top, 50)

        Text(verbatim: "\(displayValue.formatted(.number.precision(.fractionLength(2))))×")
          .font(.largeTitle)
          .fontWeight(.medium)
          .foregroundColor(.primary)

        HStack(spacing: 12) {
          Button(action: {
            if model.isEditing {
              onEditingDecrease()
            } else {
              model.onDecrease()
            }
          }) {
            Circle()
              .stroke(Color.primary.opacity(0.3), lineWidth: 2)
              .frame(width: 40, height: 40)
              .overlay {
                Image(systemName: "minus")
                  .font(.title2)
                  .foregroundColor(.primary)
              }
          }
          .disabled(displayValue <= model.range.lowerBound)

          Slider(
            value: Binding(
              get: { displayValue },
              set: { newValue in
                if model.isEditing, let index = model.editingPresetIndex {
                  let rounded = (newValue / model.step).rounded() * model.step
                  model.onPresetChanged(at: index, newValue: rounded)
                } else {
                  model.onValueChanged(newValue)
                }
              }
            ),
            in: model.range,
            step: model.step
          )

          Button(action: {
            if model.isEditing {
              onEditingIncrease()
            } else {
              model.onIncrease()
            }
          }) {
            Circle()
              .stroke(Color.primary.opacity(0.3), lineWidth: 2)
              .frame(width: 40, height: 40)
              .overlay {
                Image(systemName: "plus")
                  .font(.title2)
                  .foregroundColor(.primary)
              }
          }
          .disabled(displayValue >= model.range.upperBound)
        }
        .padding(.horizontal, 40)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
          ForEach(Array(model.presets.enumerated()), id: \.offset) { index, preset in
            if model.isEditing {
              editablePresetButton(for: preset, at: index)
            } else {
              presetButton(for: preset)
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
      }
      .padding(.bottom, 40)
    }
    .overlay(alignment: .topLeading) {
      Button(model.isEditing ? "Done" : "Edit") {
        model.onToggleEdit()
      }
      .buttonStyle(.bordered)
      .tint(.primary)
      .padding()
    }
  }

  private func onEditingIncrease() {
    guard let index = model.editingPresetIndex, let current = editingValue else { return }
    let newValue = min(current + model.step, model.range.upperBound)
    let rounded = (newValue / model.step).rounded() * model.step
    model.onPresetChanged(at: index, newValue: rounded)
  }

  private func onEditingDecrease() {
    guard let index = model.editingPresetIndex, let current = editingValue else { return }
    let newValue = max(current - model.step, model.range.lowerBound)
    let rounded = (newValue / model.step).rounded() * model.step
    model.onPresetChanged(at: index, newValue: rounded)
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
            Text(preset, format: .number.precision(.fractionLength(2)))
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

  @ViewBuilder
  private func editablePresetButton(for preset: Double, at index: Int) -> some View {
    let isSelected = model.editingPresetIndex == index
    Button(action: { model.editingPresetIndex = index }) {
      RoundedRectangle(cornerRadius: 8)
        .stroke(isSelected ? Color.accentColor : .primary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        .frame(height: 44)
        .overlay {
          Text(preset, format: .number.precision(.fractionLength(2)))
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.primary)
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
    var isEditing: Bool
    var editingPresetIndex: Int?
    let range: ClosedRange<Double>
    let step: Double
    var presets: [Double]
    let defaultValue: Double

    init(
      title: String = "",
      value: Double = 1.0,
      range: ClosedRange<Double> = 0.5...3.5,
      step: Double = 0.05,
      presets: [Double] = [0.7, 1.0, 1.2, 1.5, 1.7, 2.0],
      defaultValue: Double = 1.0,
      isPresented: Bool = false,
      isEditing: Bool = false
    ) {
      self.title = title
      self.value = value
      self.range = range
      self.step = step
      self.presets = presets
      self.defaultValue = defaultValue
      self.isPresented = isPresented
      self.isEditing = isEditing
    }

    func onIncrease() {}
    func onDecrease() {}
    func onValueChanged(_ value: Double) {}
    func onToggleEdit() {
      isEditing.toggle()
      editingPresetIndex = isEditing ? 0 : nil
    }
    func onPresetChanged(at index: Int, newValue: Double) {
      guard presets.indices.contains(index) else { return }
      presets[index] = newValue
    }
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
