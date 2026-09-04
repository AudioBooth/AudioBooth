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
      let entry = await getCurrentBookEntry()
      completion(entry)
    }
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<AudioBoothWidgetEntry>) -> Void
  ) {
    Task {
      let entry = await getCurrentBookEntry()
      let timeline = Timeline(entries: [entry], policy: .never)
      completion(timeline)
    }
  }

  @MainActor
  private func getCurrentBookEntry() async -> AudioBoothWidgetEntry {
    let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")

    guard let data = sharedDefaults?.data(forKey: "playbackState"),
      let playbackState = try? JSONDecoder().decode(PlaybackState.self, from: data)
    else {
      let (recentBooks, recentBookImages) = await fetchRecentBooks()
      return AudioBoothWidgetEntry(
        date: Date(),
        playbackState: nil,
        coverImage: nil,
        recentBooks: recentBooks,
        recentBookImages: recentBookImages
      )
    }

    var coverImage: UIImage?
    if let coverURL = playbackState.coverURL {
      var thumbnailURL = coverURL
      if var components = URLComponents(url: coverURL, resolvingAgainstBaseURL: false) {
        components.query = "width=500"
        thumbnailURL = components.url ?? coverURL
      }

      do {
        let request = ImageRequest(url: thumbnailURL, processors: [ImageProcessors.Resize(width: 500, unit: .pixels)])
        coverImage = try await ImagePipeline.shared.image(for: request)
      } catch {
      }
    }

    let (recentBooks, recentBookImages) = await fetchRecentBooks()

    return AudioBoothWidgetEntry(
      date: Date(),
      playbackState: playbackState,
      coverImage: coverImage,
      recentBooks: recentBooks,
      recentBookImages: recentBookImages
    )
  }

  @MainActor
  private func fetchRecentBooks() async -> ([BookListEntry], [String: UIImage]) {
    let sharedDefaults = UserDefaults(suiteName: "group.me.jgrenier.audioBS")

    guard let data = sharedDefaults?.data(forKey: "recentBooks"),
      let books = try? JSONDecoder().decode([BookListEntry].self, from: data)
    else {
      return ([], [:])
    }

    var images: [String: UIImage] = [:]

    for book in books {
      guard let coverURL = book.coverURL else { continue }

      var thumbnailURL = coverURL
      if var components = URLComponents(url: coverURL, resolvingAgainstBaseURL: false) {
        components.query = "width=200"
        thumbnailURL = components.url ?? coverURL
      }

      do {
        let request = ImageRequest(url: thumbnailURL, processors: [ImageProcessors.Resize(width: 200, unit: .pixels)])
        let image = try await ImagePipeline.shared.image(for: request)
        images[book.bookID] = image
      } catch {
      }
    }

    return (books, images)
  }
}
