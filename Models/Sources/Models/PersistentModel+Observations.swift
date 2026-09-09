import CoreData
import Logging
import SwiftData

extension PersistentModel {
  public static func observe<Value: Equatable & Sendable>(
    where keyPath: KeyPath<Self, Value> & Sendable,
    equals value: Value
  ) -> AsyncStream<Self> {
    let entityName = String(describing: Self.self)
    return AsyncStream { continuation in
      let task = Task { @MainActor in
        let ctx = ModelContextProvider.shared.context
        let descriptor = FetchDescriptor<Self>()
        var targetID: PersistentIdentifier?

        do {
          let items = try ctx.fetch(descriptor)
          if let model = items.first(where: { $0[keyPath: keyPath] == value }) {
            targetID = model.persistentModelID
            nonisolated(unsafe) let model = model
            continuation.yield(model)
          }
        } catch {
          AppLogger.persistence.error("Failed to fetch \(entityName) for observation: \(error)")
        }

        for await notification in NotificationCenter.default.notifications(
          named: ModelContext.didSave
        ) {
          guard
            let modelContext = notification.object as? ModelContext,
            let userInfo = notification.userInfo
          else { continue }

          let inserts = (userInfo[NSInsertedObjectsKey] as? [PersistentIdentifier]) ?? []
          let updates = (userInfo[NSUpdatedObjectsKey] as? [PersistentIdentifier]) ?? []
          let deletes = (userInfo[NSDeletedObjectsKey] as? [PersistentIdentifier]) ?? []

          if let identifier = targetID, deletes.contains(identifier) {
            targetID = nil
          }

          if let identifier = targetID {
            guard
              inserts.contains(identifier) || updates.contains(identifier),
              let matched = modelContext.model(for: identifier) as? Self,
              !matched.isDeleted
            else { continue }

            nonisolated(unsafe) let model = matched
            continuation.yield(model)
          } else {
            for identifier in inserts where identifier.entityName == entityName {
              guard
                let matched = modelContext.model(for: identifier) as? Self,
                !matched.isDeleted,
                matched[keyPath: keyPath] == value
              else { continue }

              targetID = identifier
              nonisolated(unsafe) let model = matched
              continuation.yield(model)
              break
            }
          }
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  public static func observeAll() -> AsyncStream<[Self]> {
    AsyncStream { continuation in
      let task = Task { @MainActor in
        let ctx = ModelContextProvider.shared.context
        let descriptor = FetchDescriptor<Self>()
        let entityName = String(describing: Self.self)

        let fetchData = { @MainActor in
          do {
            let items = try ctx.fetch(descriptor)
            nonisolated(unsafe) let result = items
            continuation.yield(result)
          } catch {
            continuation.yield([])
          }
        }

        fetchData()

        for await notification in NotificationCenter.default.notifications(
          named: ModelContext.didSave
        ) {
          guard let userInfo = notification.userInfo else { continue }

          let inserts = (userInfo[NSInsertedObjectsKey] as? [PersistentIdentifier]) ?? []
          let updates = (userInfo[NSUpdatedObjectsKey] as? [PersistentIdentifier]) ?? []
          let deletes = (userInfo[NSDeletedObjectsKey] as? [PersistentIdentifier]) ?? []

          let allChanges = inserts + updates + deletes
          let hasRelevantChanges = allChanges.contains { identifier in
            identifier.entityName == entityName
          }

          if hasRelevantChanges {
            fetchData()
          }
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
