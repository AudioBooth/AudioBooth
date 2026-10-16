import Foundation
import Models
import UIKit
import WidgetKit

struct BookListEntry: Codable {
  let bookID: String
  let title: String
  let author: String
  let coverURL: URL?
}

struct AudioBoothWidgetEntry: TimelineEntry {
  let date: Date
  let playbackState: PlaybackState?
  let coverImage: UIImage?
  let recentBooks: [BookListEntry]
  let recentBookImages: [String: UIImage]
}

struct AudioBoothWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> AudioBoothWidgetEntry {
    AudioBoothWidgetEntry(
      date: Date(),
      playbackState: nil,
      coverImage: nil,
      recentBooks: [],
      recentBookImages: [:]
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (AudioBoothWidgetEntry) -> Void) {
    Task {
      let entry = await getCurrentBookEntry(for: context.family)
      completion(entry)
    }
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<AudioBoothWidgetEntry>) -> Void
  ) {
    Task {
      let entry = await getCurrentBookEntry(for: context.family)
      let timeline = Timeline(entries: [entry], policy: .never)
      completion(timeline)
    }
  }

  /// Only the covers the family actually draws are loaded: small and medium show the
  /// now playing cover, large shows the recent books, and lock screen widgets show none.
  private func getCurrentBookEntry(for family: WidgetFamily) async -> AudioBoothWidgetEntry {
    let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")

    let playbackState = sharedDefaults?.data(forKey: "playbackState").flatMap {
      try? JSONDecoder().decode(PlaybackState.self, from: $0)
    }
    let recentBooks =
      sharedDefaults?.data(forKey: "recentBooks").flatMap {
        try? JSONDecoder().decode([BookListEntry].self, from: $0)
      } ?? []

    var coverImage: UIImage?
    if family == .systemSmall || family == .systemMedium, let coverURL = playbackState?.coverURL {
      coverImage = await CoverImageLoader.image(from: coverURL, maxPixelSize: CoverSize.nowPlaying)
    }

    var recentBookImages: [String: UIImage] = [:]
    if family == .systemLarge {
      for book in recentBooks {
        guard let coverURL = book.coverURL else { continue }
        recentBookImages[book.bookID] = await CoverImageLoader.image(
          from: coverURL,
          maxPixelSize: CoverSize.recentBook
        )
      }
    }

    return AudioBoothWidgetEntry(
      date: Date(),
      playbackState: playbackState,
      coverImage: coverImage,
      recentBooks: recentBooks,
      recentBookImages: recentBookImages
    )
  }
}

/// Pixel sizes for the covers drawn by the home screen widget views, at 3x scale.
private enum CoverSize {
  /// The 120pt cover of the medium widget, also enough for the 70pt small one.
  static let nowPlaying = 360
  /// The 50pt rows of the large widget.
  static let recentBook = 150
}
