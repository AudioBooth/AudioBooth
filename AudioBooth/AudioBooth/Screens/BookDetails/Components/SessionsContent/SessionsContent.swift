import Combine
import SwiftUI

struct SessionsContent: View {
  @Environment(\.appTheme) var theme
  @ObservedObject var model: Model

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, session in
        let showDate = index == 0 || model.sessions[index - 1].dateKey != session.dateKey
        sessionRow(session, showDate: showDate, isLast: index == model.sessions.count - 1)
      }

      if model.hasMorePages {
        Button(action: model.onLoadMore) {
          if model.isLoadingMore {
            ProgressView()
              .frame(maxWidth: .infinity)
          } else {
            Text("Load More")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
        .disabled(model.isLoadingMore)
        .padding(.top, 16)
      }
    }
    .padding()
    .background(theme.colors.background.card)
    .cornerRadius(8)
  }

  private func sessionRow(_ session: Session, showDate: Bool, isLast: Bool) -> some View {
    HStack(alignment: .top, spacing: 12) {
      if showDate {
        VStack(spacing: 0) {
          Text(session.dayNumber)
            .font(.title2)
            .fontWeight(.bold)
            .foregroundStyle(Color.accentColor)

          Text(session.monthAbbreviation)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(Color.accentColor)

          if let year = session.year {
            Text(year)
              .font(.caption2)
              .foregroundStyle(Color.accentColor.opacity(0.8))
          }
        }
        .frame(width: 44)
      } else {
        Color.clear
          .frame(width: 44)
      }

      VStack(spacing: 0) {
        Circle()
          .fill(Color.accentColor)
          .frame(width: 12, height: 12)

        if !isLast {
          Rectangle()
            .fill(Color.accentColor)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
        }
      }
      .frame(width: 12)

      VStack(alignment: .leading, spacing: 6) {
        Text(session.timeRange)
          .font(.headline)
          .lineLimit(1)

        HStack {
          ProgressView(value: session.progress)
            .tint(.accentColor)

          Text(session.progress.formatted(.percent.precision(.fractionLength(0))))
            .font(.caption)
            .monospacedDigit()
        }
      }
      .padding(.bottom, 20)

      Text(session.durationText)
        .font(.subheadline)
        .fontWeight(.medium)
        .monospacedDigit()
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(.capsule)
    }
  }
}

extension SessionsContent {
  struct Session {
    let id: String
    let dateKey: String
    let dayNumber: String
    let monthAbbreviation: String
    let year: String?
    let timeRange: String
    let durationText: String
    let progress: Double
  }

  @Observable
  class Model: ObservableObject {
    var sessions: [Session]
    var hasMorePages: Bool
    var isLoadingMore: Bool

    func onLoadMore() {}

    init(
      sessions: [Session] = [],
      hasMorePages: Bool = false,
      isLoadingMore: Bool = false
    ) {
      self.sessions = sessions
      self.hasMorePages = hasMorePages
      self.isLoadingMore = isLoadingMore
    }
  }
}
