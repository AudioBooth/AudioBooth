import Foundation
import SwiftData

@MainActor
public final class ModelContextProvider {
  public static let shared = ModelContextProvider()

  public let container: ModelContainer
  public let context: ModelContext

  private init() {
    let schema = Schema([RecentlyPlayedItem.self, MediaProgress.self])

    let dbURL = URL.documentsDirectory.appending(path: "AudiobookshelfData.sqlite")
    let configuration = ModelConfiguration(
      schema: schema,
      url: dbURL,
      allowsSave: true
    )

    do {
      self.container = try ModelContainer(for: schema, configurations: [configuration])
    } catch {
      print("❌ Failed to create persistent model container: \(error)")
      print("🔄 Clearing data and creating fresh container...")

      try? FileManager.default.removeItem(at: dbURL)
      try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("wal"))
      try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("shm"))

      print("✅ Cleared existing database files")

      do {
        self.container = try ModelContainer(for: schema, configurations: [configuration])
      } catch {
        print("❌ Failed to create fresh container: \(error)")
        fatalError("Could not create ModelContainer even after clearing data")
      }
    }

    self.context = container.mainContext
  }
}
