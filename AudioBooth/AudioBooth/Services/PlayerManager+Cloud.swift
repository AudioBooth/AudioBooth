import API
import Foundation

extension PlayerManager {
  private var cloud: NSUbiquitousKeyValueStore? {
    UserPreferences.shared.cloud
  }

  private var isCloudSyncEnabled: Bool {
    UserPreferences.shared.iCloudSyncEnabled
  }

  /// A cross-device-stable identifier for the active server.
  ///
  /// The per-connection `serverID` is a locally-generated UUID, so it differs on
  /// every device even for the same server and cannot be used to scope shared
  /// state. The normalized base URL is the same on every device that connects to
  /// the same server, so we key the cloud queue on that instead.
  private var serverScope: String? {
    guard let url = Audiobookshelf.shared.authentication.server?.baseURL else { return nil }
    var scope = url.absoluteString.lowercased()
    while scope.hasSuffix("/") { scope.removeLast() }
    return scope
  }

  /// The `NSUbiquitousKeyValueStore` key holding the queue for the active server.
  /// Namespacing per server keeps each server's queue independent so a device on
  /// one server never overwrites another server's queue.
  private var currentCloudQueueKey: String? {
    guard let serverScope else { return nil }
    return "\(Self.cloudQueueKey).\(serverScope)"
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

    guard isCloudSyncEnabled else { return }
    cloud.synchronize()

    guard let key = currentCloudQueueKey else { return }

    // The cloud is the source of truth when it already holds a queue for this
    // server. Otherwise seed it from whatever this device has locally, so an
    // existing queue is uploaded without an empty-queue push clobbering it.
    if cloud.data(forKey: key) != nil {
      syncQueueFromCloud()
    } else if !queue.isEmpty {
      syncQueueToCloud()
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

    // Ignore notifications that don't touch any queue key in our namespace.
    if let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
      !changedKeys.contains(where: { $0.hasPrefix(Self.cloudQueueKey) })
    {
      return
    }

    syncQueueFromCloud()
  }

  /// Adopt the queue stored in the cloud for the active server, if it differs
  /// from what we already have.
  func syncQueueFromCloud() {
    guard isCloudSyncEnabled,
      let cloud,
      let key = currentCloudQueueKey,
      let data = cloud.data(forKey: key),
      let items = try? JSONDecoder().decode([QueueItem].self, from: data),
      items != queue
    else { return }

    // Applying a remote change must not echo back to the cloud. The `queue`
    // didSet still persists locally via `saveQueue()`; `syncQueueToCloud()` is
    // skipped while this flag is set.
    isApplyingCloudQueueChange = true
    reorderQueue(items)
    isApplyingCloudQueueChange = false
  }

  /// Push the current queue to the cloud for the active server. No-op while
  /// applying a remote change, while sync is disabled, on contributor builds
  /// (where `cloud` is nil), or before a server is active.
  func syncQueueToCloud() {
    guard isCloudSyncEnabled,
      !isApplyingCloudQueueChange,
      let cloud,
      let key = currentCloudQueueKey,
      let data = try? JSONEncoder().encode(queue)
    else { return }

    cloud.set(data, forKey: key)
    cloud.synchronize()
  }

  func purgeQueueFromCloud() {
    guard let cloud else { return }
    // Remove every queue key in our namespace (all servers, plus any legacy key).
    for key in cloud.dictionaryRepresentation.keys where key.hasPrefix(Self.cloudQueueKey) {
      cloud.removeObject(forKey: key)
    }
    cloud.synchronize()
  }
}
