import SwiftUI

struct DailyGoalCard: View {
  @Environment(\.appTheme) var theme
  let todayTime: Double
  let goalMinutes: Int
  let onEdit: () -> Void

  var body: some View {
    let todayMinutes = Int(todayTime / 60)
    let isSet = goalMinutes > 0
    let progress = isSet ? Double(todayMinutes) / Double(goalMinutes) : 0
    let remaining = max(goalMinutes - todayMinutes, 0)
    let over = max(todayMinutes - goalMinutes, 0)
    let percent = Int((progress * 100).rounded())

    HStack(alignment: .center, spacing: 18) {
      goalRing(isSet: isSet, progress: progress, percent: percent)
        .frame(width: 92, height: 92)

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("DAILY GOAL")
            .font(.caption2)
            .fontWeight(.semibold)
            .tracking(1)
            .foregroundStyle(.secondary)

          Spacer()

          if isSet {
            Button(action: onEdit) {
              Image(systemName: "pencil")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.12))
                .clipShape(.circle)
            }
            .buttonStyle(.plain)
          } else {
            Button(action: onEdit) {
              Label("Set", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.accentColor)
                .clipShape(.capsule)
            }
            .buttonStyle(.plain)
          }
        }

        if isSet {
          Text(verbatim: "\(todayMinutes)")
            .font(.title.weight(.bold))
            .monospacedDigit()
            +

            Text(verbatim: "/ \(goalMinutes)")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            +

            Text("min")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)

          if over > 0 {
            Text("Goal smashed, ^[\(over) min](inflect: true) over")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(Color.accentColor)
          } else if remaining > 0 {
            Text("^[\(remaining) min](inflect: true) to go today")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
            Text("Goal reached!")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(Color.accentColor)
          }
        } else {
          Text("Not set")
            .font(.title2.weight(.bold))
          Text("Tap to set a daily goal")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16)
    .frame(maxWidth: .infinity)
    .background(theme.colors.background.card)
    .clipShape(.rect(cornerRadius: 20))
  }

  @ViewBuilder
  private func goalRing(isSet: Bool, progress: Double, percent: Int) -> some View {
    ZStack {
      Circle()
        .stroke(Color.secondary.opacity(0.10), lineWidth: 8)

      if isSet {
        Circle()
          .trim(from: 0, to: min(CGFloat(progress), 1.0))
          .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(.easeInOut, value: progress)

        Text(percent, format: .percent)
          .font(.system(size: 22, weight: .bold, design: .rounded))
          .foregroundStyle(Color.accentColor)
          .monospacedDigit()
      } else {
        Circle()
          .stroke(
            Color.secondary.opacity(0.3),
            style: StrokeStyle(lineWidth: 8, lineCap: .round, dash: [0, 12])
          )

        Image(systemName: "bolt")
          .font(.title3)
          .foregroundStyle(Color.secondary.opacity(0.5))
      }
    }
  }
}

#Preview("Not set") {
  DailyGoalCard(todayTime: 0, goalMinutes: 0, onEdit: {})
    .padding()
}

#Preview("In progress") {
  DailyGoalCard(todayTime: 28 * 60, goalMinutes: 45, onEdit: {})
    .padding()
}

#Preview("Goal smashed") {
  DailyGoalCard(todayTime: 28 * 60, goalMinutes: 20, onEdit: {})
    .padding()
}
