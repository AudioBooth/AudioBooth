import Foundation
import Models
import Nuke
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

  @MainActor
  private func getCurrentBookEntry(for family: WidgetFamily) async -> AudioBoothWidgetEntry {
    let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")

    let playbackState = sharedDefaults?.data(forKey: "playbackState")
      .flatMap { try? JSONDecoder().decode(PlaybackState.self, from: $0) }

    var coverImage: UIImage?
    if family == .systemSmall || family == .systemMedium, let coverURL = playbackState?.coverURL {
      coverImage = await loadCover(from: coverURL, pixelSize: 360)
    }

    let (recentBooks, recentBookImages) = await fetchRecentBooks(loadImages: family == .systemLarge)

    return AudioBoothWidgetEntry(
      date: Date(),
      playbackState: playbackState,
      coverImage: coverImage,
      recentBooks: recentBooks,
      recentBookImages: recentBookImages
    )
  }

  @MainActor
  private func fetchRecentBooks(loadImages: Bool) async -> ([BookListEntry], [String: UIImage]) {
    let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")

    guard let data = sharedDefaults?.data(forKey: "recentBooks"),
      let books = try? JSONDecoder().decode([BookListEntry].self, from: data)
    else {
      return ([], [:])
    }

    guard loadImages else { return (books, [:]) }

    var images: [String: UIImage] = [:]

    for book in books {
      guard let coverURL = book.coverURL else { continue }
      images[book.bookID] = await loadCover(from: coverURL, pixelSize: 150)
    }

    return (books, images)
  }

  @MainActor
  private func loadCover(from url: URL, pixelSize: Int) async -> UIImage? {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let queryItems = (components?.queryItems ?? []).filter { $0.name != "raw" && $0.name != "width" }
    components?.queryItems = queryItems + [URLQueryItem(name: "width", value: String(pixelSize))]
    let thumbnailURL = components?.url ?? url

    var request = ImageRequest(url: thumbnailURL)
    request.thumbnail = ImageRequest.ThumbnailOptions(
      size: CGSize(width: pixelSize, height: pixelSize),
      unit: .pixels,
      contentMode: .aspectFill
    )

    return try? await ImagePipeline.shared.image(for: request)
  }
}
