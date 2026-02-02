import Foundation

public enum HomeSection: String, CaseIterable, Identifiable, Codable {
  case listeningStats = "listening-stats"
  case pinnedPlaylist = "pinned-playlist"
  case continueListening = "continue-listening"
  case continueReading = "continue-reading"
  case continueSeries = "continue-series"
  case recentlyAdded = "recently-added"
  case recentSeries = "recent-series"
  case discover = "discover"
  case listenAgain = "listen-again"
  case newestAuthors = "newest-authors"

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .listeningStats: String(localized: "Listening Stats")
    case .pinnedPlaylist: String(localized: "Pinned Playlist")
    case .continueListening: String(localized: "Continue Listening")
    case .continueReading: String(localized: "Continue Reading")
    case .continueSeries: String(localized: "Continue Series")
    case .recentlyAdded: String(localized: "Recently Added")
    case .recentSeries: String(localized: "Recent Series")
    case .discover: String(localized: "Discover")
    case .listenAgain: String(localized: "Listen Again")
    case .newestAuthors: String(localized: "Newest Authors")
    }
  }

  public var canBeDisabled: Bool {
    ![.pinnedPlaylist, .continueListening, .continueReading].contains(self)
  }

  public static var defaultCases: [HomeSection] {
    [
      .continueListening,
      .continueReading,
      .continueSeries,
      .recentlyAdded,
      .recentSeries,
      .discover,
      .listenAgain,
      .newestAuthors,
    ]
  }
}
