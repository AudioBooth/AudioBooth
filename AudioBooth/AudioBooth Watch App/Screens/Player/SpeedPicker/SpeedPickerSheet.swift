import Combine
import SwiftUI

struct SpeedPickerSheet: View {
  @Environment(\.dismiss) private var dismiss

  @ObservedObject var model: Model

  @State private var crownValue: Double = 0
  @FocusState private var isFocused: Bool

  private let speeds: [Float] = [0.7, 1.0, 1.2, 1.5, 1.7, 2.0]

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        Text(verbatim: "\(model.speed.formatted(.number.precision(.fractionLength(0...2))))×")
          .font(.title2)
          .fontWeight(.medium)
          .focused($isFocused)
          .digitalCrownRotation(
            $crownValue,
            from: 0.5,
            through: 3.5,
            by: 0.05,
            sensitivity: .low
          )
          .onChange(of: crownValue) { _, newValue in
            let rounded = Float((newValue / 0.05).rounded() * 0.05)
            model.onSpeedChanged(rounded)
          }

        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
          ForEach(speeds, id: \.self) { speed in
            speedButton(for: speed)
          }
        }
        .padding(.horizontal)
      }
      .padding(.top)
    }
    .onAppear {
      crownValue = Double(model.speed)
      isFocused = true
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
