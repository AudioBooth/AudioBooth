import API
import Foundation

extension PlayerManager {
  /// Payload mirrored through `NSUbiquitousKeyValueStore` so the "Playing Next"
  /// queue stays in sync across the user's devices. The queue is scoped to a
  /// server so a device connected to a different server never adopts a foreign
  /// queue.
  private struct CloudQueuePayload: Codable {
    let serverID: String?
    let queue: [QueueItem]
  }

  private var cloud: NSUbiquitousKeyValueStore? {
    UserPreferences.shared.cloud
  }

  private var isCloudSyncEnabled: Bool {
    UserPreferences.shared.iCloudSyncEnabled
  }

  func setupQueueCloudSync() {
    guard let cloud else { return }

    cloudQueueObserver = NotificationCenter.default.addObserver(
      forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: cloud,
      queue: .main
    ) { [weak self] notification in
      self?.handleCloudQueueChange(notification)
    }

    if isCloudSyncEnabled {
      cloud.synchronize()
      syncQueueFromCloud()
    }
  }

  private func handleCloudQueueChange(_ notification: Notification) {
    guard isCloudSyncEnabled else { return }

    guard let userInfo = notification.userInfo,
      let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
    else { return }

    guard
      changeReason == NSUbiquitousKeyValueStoreServerChange
        || changeReason == NSUbiquitousKeyValueStoreInitialSyncChange
    else { return }

    // Ignore notifications that don't touch the queue key.
    if let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
      !changedKeys.contains(Self.cloudQueueKey)
    {
      return
    }

    syncQueueFromCloud()
  }

  /// Adopt the queue stored in the cloud, if it belongs to the active server and
  /// differs from what we already have.
  func syncQueueFromCloud() {
    guard isCloudSyncEnabled,
      let cloud,
      let data = cloud.data(forKey: Self.cloudQueueKey),
      let payload = try? JSONDecoder().decode(CloudQueuePayload.self, from: data)
    else { return }

    guard payload.serverID == Audiobookshelf.shared.libraries.current?.serverID else { return }
    guard payload.queue != queue else { return }

    // Applying a remote change must not echo back to the cloud. The `queue`
    // didSet still persists locally via `saveQueue()`; `syncQueueToCloud()` is
    // skipped while this flag is set.
    isApplyingCloudQueueChange = true
    reorderQueue(payload.queue)
    isApplyingCloudQueueChange = false
  }

  /// Push the current queue to the cloud. No-op while applying a remote change,
  /// while sync is disabled, or on contributor builds (where `cloud` is nil).
  func syncQueueToCloud() {
    guard isCloudSyncEnabled,
      !isApplyingCloudQueueChange,
      let cloud
    else { return }

    let payload = CloudQueuePayload(
      serverID: Audiobookshelf.shared.libraries.current?.serverID,
      queue: queue
    )

    if let data = try? JSONEncoder().encode(payload) {
      cloud.set(data, forKey: Self.cloudQueueKey)
      cloud.synchronize()
    }
  }

  func purgeQueueFromCloud() {
    guard let cloud else { return }
    cloud.removeObject(forKey: Self.cloudQueueKey)
    cloud.synchronize()
  }
}
