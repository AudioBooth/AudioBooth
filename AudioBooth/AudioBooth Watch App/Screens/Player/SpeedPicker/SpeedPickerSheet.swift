import Combine
import SwiftUI

struct SpeedPickerSheet: View {
  @Environment(\.dismiss) private var dismiss

  @ObservedObject var model: Model

  private let speeds: [Float] = [0.7, 1.0, 1.2, 1.5, 1.7, 2.0]
  private let step: Float = 0.05
  private let minSpeed: Float = 0.5
  private let maxSpeed: Float = 3.5

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        Stepper(
          value: Binding(
            get: { model.speed },
            set: { model.onSpeedChanged(($0 / step).rounded() * step) }
          ),
          in: minSpeed...maxSpeed,
          step: step
        ) {
          Text(verbatim: "\(model.speed.formatted(.number.precision(.fractionLength(0...2))))×")
            .font(.title3)
            .fontWeight(.medium)
        }
        .padding(.horizontal)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
          ForEach(speeds, id: \.self) { speed in
            speedButton(for: speed)
          }
        }
        .padding(.horizontal)
      }
      .padding(.top)
    }
    .navigationTitle("Speed")
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private func speedButton(for speed: Float) -> some View {
    let isSelected = abs(model.speed - speed) < 0.01

    Button {
      model.onSpeedChanged(speed)
      dismiss()
    } label: {
      VStack(spacing: 4) {
        Text(speed, format: .number.precision(.fractionLength(0...2)))
          .font(.body)
          .fontWeight(isSelected ? .bold : .regular)

        if speed == 1.0 {
          Text("DEFAULT")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.orange)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? Color.orange : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
  }
}

extension SpeedPickerSheet {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()

    var speed: Float
    var isPresented: Bool = false

    init(speed: Float = 1.0) {
      self.speed = speed
    }

    func onSpeedChanged(_ speed: Float) {}
  }
}

#Preview {
  NavigationStack {
    SpeedPickerSheet(
      model: SpeedPickerSheet.Model(speed: 1.5)
    )
  }
}
