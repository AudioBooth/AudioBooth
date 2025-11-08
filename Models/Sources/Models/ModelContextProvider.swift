import Foundation
import OSLog
import SwiftData

@MainActor
public final class ModelContextProvider {
  public static let shared = ModelContextProvider()

  public let container: ModelContainer
  public let context: ModelContext

  private init() {
    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else {
      fatalError("App Group container not found. Check entitlements configuration.")
    }

    let dbURL = containerURL.appending(path: "AudiobookshelfData.sqlite")

    Self.migrateDatabaseIfNeeded(to: dbURL)
    Self.migrateAudiobooksFolder()

    let configuration = ModelConfiguration(url: dbURL, allowsSave: true)

    do {
      let schema = Schema(versionedSchema: AudiobookshelfSchema.self)
      self.container = try ModelContainer(for: schema, configurations: configuration)
      AppLogger.persistence.info("ModelContainer created successfully")
    } catch {
      AppLogger.persistence.error("Failed to create persistent model container: \(error)")
      AppLogger.persistence.info("Clearing data and creating fresh container...")

      let fileExtensions = ["", "-shm", "-wal"]
      for ext in fileExtensions {
        let fileURL = URL(fileURLWithPath: dbURL.path + ext)
        try? FileManager.default.removeItem(at: fileURL)
      }

      AppLogger.persistence.info("Cleared existing database files")

      do {
        let schema = Schema(versionedSchema: AudiobookshelfSchema.self)
        self.container = try ModelContainer(for: schema, configurations: configuration)
        AppLogger.persistence.info("Fresh container created successfully")
      } catch {
        AppLogger.persistence.error("Failed to create fresh container: \(error)")
        fatalError("Could not create ModelContainer even after clearing data")
      }
    }

    self.context = container.mainContext
  }

  private static func migrateDatabaseIfNeeded(to newURL: URL) {
    let fileManager = FileManager.default
    let oldURL = URL.documentsDirectory.appending(path: "AudiobookshelfData.sqlite")

    guard fileManager.fileExists(atPath: oldURL.path),
      !fileManager.fileExists(atPath: newURL.path)
    else {
      if fileManager.fileExists(atPath: newURL.path) {
        AppLogger.persistence.info("Database already exists at new location, skipping migration")
      }
      return
    }

    AppLogger.persistence.info("Migrating database from old location to App Group container...")

    do {
      let fileExtensions = ["", "-shm", "-wal"]

      for ext in fileExtensions {
        let sourceURL = URL(fileURLWithPath: oldURL.path + ext)
        let destinationURL = URL(fileURLWithPath: newURL.path + ext)

        if fileManager.fileExists(atPath: sourceURL.path) {
          try fileManager.moveItem(at: sourceURL, to: destinationURL)
          let fileType = ext.isEmpty ? "main database" : "\(ext) file"
          AppLogger.persistence.info("Migrated \(fileType)")
        }
      }

      AppLogger.persistence.info("Database migration completed successfully")

    } catch {
      AppLogger.persistence.error("Database migration failed: \(error)")
      AppLogger.persistence.info("App will create fresh database at new location")
    }
  }

  private static func migrateAudiobooksFolder() {
    let fileManager = FileManager.default

    guard
      let appGroupURL = fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else {
      AppLogger.persistence.error("Failed to get app group URL for audiobooks migration")
      return
    }

    let oldAudiobooksURL = URL.documentsDirectory.appending(path: "audiobooks")
    var newAudiobooksURL = appGroupURL.appending(path: "audiobooks")

    guard fileManager.fileExists(atPath: oldAudiobooksURL.path) else {
      AppLogger.persistence.info("No audiobooks folder to migrate")
      return
    }

    guard !fileManager.fileExists(atPath: newAudiobooksURL.path) else {
      AppLogger.persistence.info(
        "Audiobooks folder already exists at new location, skipping migration")
      return
    }

    AppLogger.persistence.info("Migrating audiobooks folder to App Group container...")

    do {
      try fileManager.copyItem(at: oldAudiobooksURL, to: newAudiobooksURL)
      AppLogger.persistence.info("Audiobooks folder migration completed successfully")

      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      try? newAudiobooksURL.setResourceValues(resourceValues)
      AppLogger.persistence.info("Excluded audiobooks folder from iCloud backup")

      try fileManager.removeItem(at: oldAudiobooksURL)
      AppLogger.persistence.info("Cleaned up old audiobooks folder")
    } catch {
      AppLogger.persistence.error("Audiobooks folder migration failed: \(error)")
      AppLogger.persistence.info("Downloaded books may need to be re-downloaded")
    }
  }
}
