import Foundation
import Logging
import SwiftData

@MainActor
public final class ModelContextProvider {
  public static let shared = ModelContextProvider()

  private var containers: [String: ModelContainer] = [:]
  private var contexts: [String: ModelContext] = [:]
  public private(set) var activeServerID: String?

  public var container: ModelContainer? {
    guard let serverID = activeServerID else { return nil }
    return containers[serverID]
  }

  public var context: ModelContext {
    if let activeServerID, let context = contexts[activeServerID] {
      return context
    }

    assertionFailure("No active server. Database access requires user to be logged in.")
    AppLogger.persistence.warning(
      "Accessing context without active server, using fallback database"
    )

    let serverID = "fallback"
    if let fallbackContext = contexts[serverID] {
      return fallbackContext
    }

    do {
      let fallbackContainer = try createContainer(for: serverID)
      containers[serverID] = fallbackContainer
      contexts[serverID] = fallbackContainer.mainContext
      return fallbackContainer.mainContext
    } catch {
      AppLogger.persistence.error(
        "Failed to create fallback container: \(error.localizedDescription)"
      )
      fatalError("Failed to create fallback database container")
    }
  }

  private init() {}

  public func context(for serverID: String) throws -> ModelContext {
    if let context = contexts[serverID] {
      return context
    }

    let container = try createContainer(for: serverID)
    containers[serverID] = container
    contexts[serverID] = container.mainContext
    return container.mainContext
  }

  public func switchToServer(_ serverID: String, serverURL: URL) throws {
    if containers[serverID] == nil {
      let container = try createContainer(for: serverID)
      containers[serverID] = container
      contexts[serverID] = container.mainContext
    }
    activeServerID = serverID
  }

  public func removeServer(_ serverID: String) throws {
    containers[serverID] = nil
    contexts[serverID] = nil

    if activeServerID == serverID {
      activeServerID = nil
    }

    let dbURL = databaseURL(for: serverID)
    let fileExtensions = ["", "-shm", "-wal"]
    for ext in fileExtensions {
      let fileURL = URL(fileURLWithPath: dbURL.path + ext)
      try? FileManager.default.removeItem(at: fileURL)
    }
  }

  private func createContainer(for serverID: String) throws -> ModelContainer {
    let dbURL = databaseURL(for: serverID)
    let configuration = ModelConfiguration(url: dbURL, allowsSave: true)

    do {
      let schema = Schema(versionedSchema: AudiobookshelfSchema.self)
      let container = try ModelContainer(for: schema, configurations: configuration)
      AppLogger.persistence.info(
        "ModelContainer created successfully for server: \(serverID)"
      )
      return container
    } catch {
      AppLogger.persistence.error(
        "Failed to create persistent model container for server \(serverID): \(error)"
      )
      AppLogger.persistence.info("Clearing data and creating fresh container...")

      let fileExtensions = ["", "-shm", "-wal"]
      for ext in fileExtensions {
        let fileURL = URL(fileURLWithPath: dbURL.path + ext)
        try? FileManager.default.removeItem(at: fileURL)
      }

      AppLogger.persistence.info("Cleared existing database files")

      do {
        let schema = Schema(versionedSchema: AudiobookshelfSchema.self)
        let container = try ModelContainer(for: schema, configurations: configuration)
        AppLogger.persistence.info("Fresh container created successfully")
        return container
      } catch {
        AppLogger.persistence.error("Failed to create fresh container: \(error)")
        throw error
      }
    }
  }

  private func databaseURL(for serverID: String) -> URL {
    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.me.jgrenier.audioBS"
      )
    else {
      fatalError("App Group container not found. Check entitlements configuration.")
    }
    return
      containerURL
      .appending(path: serverID)
      .appending(path: "AudiobookshelfData.sqlite")
  }
}
