import SwiftUI

struct SpeedPickerSheet: View {
  @Binding var model: Model

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 24) {
        Text("Speed")
          .font(.title2)
          .fontWeight(.semibold)
          .foregroundColor(.primary)
          .padding(.top, 50)

        Text("\(String(format: "%.2f", model.playbackSpeed))×")
          .font(.largeTitle)
          .fontWeight(.medium)
          .foregroundColor(.primary)

        HStack(spacing: 12) {
          Button(action: { model.onSpeedDecrease() }) {
            Circle()
              .stroke(Color.primary.opacity(0.3), lineWidth: 2)
              .frame(width: 40, height: 40)
              .overlay {
                Image(systemName: "minus")
                  .font(.title2)
                  .foregroundColor(.primary)
              }
          }
          .disabled(model.playbackSpeed <= 0.7)

          Slider(
            value: Binding(
              get: { Double(model.playbackSpeed) },
              set: { model.onSpeedChanged(Float($0)) }
            ),
            in: 0.5...3.5,
            step: 0.05
          )
          .accentColor(.orange)

          Button(action: { model.onSpeedIncrease() }) {
            Circle()
              .stroke(Color.primary.opacity(0.3), lineWidth: 2)
              .frame(width: 40, height: 40)
              .overlay {
                Image(systemName: "plus")
                  .font(.title2)
                  .foregroundColor(.primary)
              }
          }
          .disabled(model.playbackSpeed >= 2.0)
        }
        .padding(.horizontal, 40)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
          ForEach(model.speeds, id: \.self) { speed in
            button(for: Float(speed))
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
      }
      .padding(.bottom, 40)
    }
    .presentationDetents([.height(400)])
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder
  func button(for speed: Float) -> some View {
    let isSelected = (model.playbackSpeed * 10).rounded() == (speed * 10).rounded()
    Button(action: {
      model.onSpeedChanged(speed)
      model.isPresented = false
    }) {
      RoundedRectangle(cornerRadius: 8)
        .stroke(isSelected ? Color.accentColor : .primary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        .frame(height: 44)
        .overlay {
          VStack(spacing: 2) {
            Text(String(format: "%.1f", speed))
              .font(.system(size: 16, weight: .medium))
              .foregroundColor(.primary)

            if speed == 1.0 {
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

extension SpeedPickerSheet {
  @Observable class Model {
    var playbackSpeed: Float = 1.0
    var isPresented: Bool = false
    let speeds = [0.7, 1.0, 1.2, 1.5, 1.7, 2.0]

    init(playbackSpeed: Float = 1.0) {
      self.playbackSpeed = playbackSpeed
    }

    func onSpeedIncrease() {}
    func onSpeedDecrease() {}
    func onSpeedChanged(_ speed: Float) {}
  }
}

extension SpeedPickerSheet.Model {
  static let mock = SpeedPickerSheet.Model(playbackSpeed: 1.0)
}

#Preview {
  SpeedPickerSheet(model: .constant(.mock))
}
