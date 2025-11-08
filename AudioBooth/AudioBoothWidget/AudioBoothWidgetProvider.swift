import Foundation
import Models
import Nuke
import SwiftData
import UIKit
import WidgetKit

struct AudioBoothWidgetEntry: TimelineEntry {
  let date: Date
  let book: LocalBook?
  let progress: MediaProgress?
  let coverImage: UIImage?
  let isPlaying: Bool
}

struct AudioBoothWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> AudioBoothWidgetEntry {
    AudioBoothWidgetEntry(date: Date(), book: nil, progress: nil, coverImage: nil, isPlaying: false)
  }

  func getSnapshot(in context: Context, completion: @escaping (AudioBoothWidgetEntry) -> Void) {
    Task {
      let entry = await getCurrentBookEntry()
      completion(entry)
    }
  }

  func getTimeline(
    in context: Context, completion: @escaping (Timeline<AudioBoothWidgetEntry>) -> Void
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

    guard let currentBookID = sharedDefaults?.string(forKey: "currentBookID") else {
      return AudioBoothWidgetEntry(
        date: Date(), book: nil, progress: nil, coverImage: nil, isPlaying: false)
    }

    let isPlaying = sharedDefaults?.bool(forKey: "isPlaying") ?? false

    let context = ModelContextProvider.shared.context
    let bookDescriptor = FetchDescriptor<LocalBook>(
      predicate: #Predicate { $0.bookID == currentBookID }
    )

    do {
      let books = try context.fetch(bookDescriptor)

      guard let book = books.first else {
        return AudioBoothWidgetEntry(
          date: Date(), book: nil, progress: nil, coverImage: nil, isPlaying: false)
      }

      let progressDescriptor = FetchDescriptor<MediaProgress>(
        predicate: #Predicate { $0.bookID == currentBookID }
      )
      let progress = try? context.fetch(progressDescriptor).first

      var coverImage: UIImage?
      if let coverURL = book.coverURL {
        var thumbnailURL = coverURL
        if var components = URLComponents(url: coverURL, resolvingAgainstBaseURL: false) {
          components.query = "width=500"
          thumbnailURL = components.url ?? coverURL
        }

        do {
          let request = ImageRequest(url: thumbnailURL)
          coverImage = try await ImagePipeline.shared.image(for: request)
        } catch {
        }
      }

      return AudioBoothWidgetEntry(
        date: Date(), book: book, progress: progress, coverImage: coverImage, isPlaying: isPlaying)
    } catch {
      return AudioBoothWidgetEntry(
        date: Date(), book: nil, progress: nil, coverImage: nil, isPlaying: false)
    }
  }
}
