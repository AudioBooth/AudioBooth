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

        // Reading a persisted property off a changed model faults it in, costing a separate
        // store fetch per object. Resolve the match once, then track it by identifier so the
        // notification loop compares identifiers instead of touching the store.
        var targetID: PersistentIdentifier?

        func locateTarget() -> Self? {
          do {
            let items = try ctx.fetch(descriptor)
            return items.first { $0[keyPath: keyPath] == value }
          } catch {
            AppLogger.persistence.error("Failed to fetch \(entityName) for observation: \(error)")
            return nil
          }
        }

        if let model = locateTarget() {
          targetID = model.persistentModelID
          nonisolated(unsafe) let model = model
          continuation.yield(model)
        }

        for await notification in NotificationCenter.default.notifications(
          named: ModelContext.didSave
        ) {
          guard
            let modelContext = notification.object as? ModelContext,
            let userInfo = notification.userInfo
          else { continue }

          let inserts = Set((userInfo[NSInsertedObjectsKey] as? [PersistentIdentifier]) ?? [])
          let updates = Set((userInfo[NSUpdatedObjectsKey] as? [PersistentIdentifier]) ?? [])
          let deletes = Set((userInfo[NSDeletedObjectsKey] as? [PersistentIdentifier]) ?? [])

          if let identifier = targetID, deletes.contains(identifier) {
            targetID = nil
          }

          if let identifier = targetID {
            guard inserts.contains(identifier) || updates.contains(identifier) else { continue }
            guard
              let matched = modelContext.model(for: identifier) as? Self,
              !matched.isDeleted
            else { continue }

            nonisolated(unsafe) let model = matched
            continuation.yield(model)
          } else if inserts.contains(where: { $0.entityName == entityName }) {
            // Nothing is being tracked yet, so only a newly inserted row can start
            // matching. Re-resolve once rather than per changed object.
            if let model = locateTarget() {
              targetID = model.persistentModelID
              nonisolated(unsafe) let model = model
              continuation.yield(model)
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
