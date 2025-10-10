import CoreData
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

        do {
          let items = try ctx.fetch(descriptor)
          let model = items.first { $0[keyPath: keyPath] == value }
          if let model {
            nonisolated(unsafe) let model = model
            continuation.yield(model)
          }
        } catch {}

        for await notification in NotificationCenter.default.notifications(
          named: ModelContext.didSave)
        {
          guard
            let modelContext = notification.object as? ModelContext,
            let userInfo = notification.userInfo
          else { continue }

          let inserts = (userInfo[NSInsertedObjectsKey] as? [PersistentIdentifier]) ?? []
          let updates = (userInfo[NSUpdatedObjectsKey] as? [PersistentIdentifier]) ?? []

          let allChanges = inserts + updates

          for identifier in allChanges {
            guard
              identifier.entityName == entityName,
              let model = modelContext.model(for: identifier) as? Self,
              !model.isDeleted,
              model[keyPath: keyPath] == value
            else { continue }

            nonisolated(unsafe) let value = model
            continuation.yield(value)
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
            continuation.yield(items)
          } catch {
            continuation.yield([])
          }
        }

        fetchData()

        for await notification in NotificationCenter.default.notifications(
          named: ModelContext.didSave)
        {
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
