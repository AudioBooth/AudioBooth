import API
import Combine
import Models
import SwiftUI

struct PlaybackSessionListView: View {
  @ObservedObject var model: Model

  var body: some View {
    List {
      ForEach(model.sessions, id: \.id) { session in
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: coverURL(for: session.libraryItemID)) { image in
              image
                .resizable()
                .aspectRatio(contentMode: .fill)
            } placeholder: {
              Rectangle()
                .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
              VStack(alignment: .leading, spacing: 0) {
                Text(session.displayTitle ?? session.libraryItemID)
                  .foregroundColor(.primary)
                  .fontWeight(.medium)
                  .font(.callout)

                if let displayAuthor = session.displayAuthor {
                  Text(displayAuthor)
                    .foregroundColor(.secondary)
                    .font(.footnote)
                }
              }
              .lineLimit(1)

              VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                  HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(
                      formatDuration(session.timeListening + session.pendingListeningTime)
                    )
                  }
                  .fontWeight(.medium)
                  .foregroundColor(.accentColor)

                  Text("•")

                  Text("\(formatTime(session.startTime)) → \(formatTime(session.currentTime))")
                }

                HStack(spacing: 6) {
                  Text(formatDate(session.updatedAt))

                  Text("•")

                  Text(session.updatedAt.formatted(date: .omitted, time: .shortened))
                }
              }
              .foregroundColor(.secondary)
              .font(.caption)
            }
          }
          .padding(.bottom, 8)

          VStack(alignment: .leading, spacing: 4) {
            HStack {
              HStack(spacing: 6) {
                Text("\(Int(session.progress * 100))% complete")

                Text("•")

                Text(formatTimeRemaining(session.duration - session.currentTime))
              }
              .foregroundColor(.secondary)

              Spacer()

              HStack(spacing: 4) {
                if session.pendingListeningTime > 0 {
                  Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.orange)
                }
                if session.isRemote {
                  Image(systemName: "network")
                    .foregroundColor(.blue)
                } else {
                  Image(systemName: "internaldrive")
                    .foregroundColor(.green)
                }
              }
            }
            .font(.caption)

            ProgressView(value: session.progress)
              .tint(.green)
          }

          Text(session.id)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.top, 10)
        }
      }
    }
    .navigationTitle("Playback Sessions")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: model.onAppear)
  }

  private func coverURL(for libraryItemID: String) -> URL? {
    guard let serverURL = Audiobookshelf.shared.serverURL else { return nil }
    var url = serverURL.appendingPathComponent("api/items/\(libraryItemID)/cover")
    url.append(queryItems: [URLQueryItem(name: "raw", value: "1")])
    return url
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    Duration.seconds(duration).formatted(
      .units(
        allowed: [.hours, .minutes, .seconds],
        width: .abbreviated,
        maximumUnitCount: 2
      )
    )
  }

  private func formatTime(_ duration: TimeInterval) -> String {
    Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond))
  }

  private func formatTimeRemaining(_ duration: TimeInterval) -> String {
    Duration.seconds(duration).formatted(
      .units(
        allowed: [.hours, .minutes],
        width: .narrow
      )
    ) + " remaining"
  }

  private func formatDate(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
      return String(localized: "Today")
    } else if calendar.isDateInYesterday(date) {
      return String(localized: "Yesterday")
    } else {
      return date.formatted(.dateTime.month().day())
    }
  }
}

extension PlaybackSessionListView {
  @MainActor
  @Observable
  class Model: ObservableObject {
    var sessions: [PlaybackSession]

    func onAppear() {}

    init(sessions: [PlaybackSession] = []) {
      self.sessions = sessions
    }
  }
}

extension PlaybackSessionListView.Model {
  static var mock = PlaybackSessionListView.Model(
    sessions: [
      PlaybackSession(
        libraryItemID: "book-1",
        startTime: 1700,
        currentTime: 1800,
        timeListening: 3020,
        pendingListeningTime: 600,
        duration: 7200,
        displayTitle: "The Great Gatsby",
        displayAuthor: "F. Scott Fitzgerald"
      ),
      PlaybackSession(
        libraryItemID: "book-2",
        startTime: 550,
        currentTime: 600,
        timeListening: 1200,
        pendingListeningTime: 0,
        duration: 3600
      ),
    ]
  )
}

#Preview {
  NavigationStack {
    PlaybackSessionListView(model: .mock)
  }
}
