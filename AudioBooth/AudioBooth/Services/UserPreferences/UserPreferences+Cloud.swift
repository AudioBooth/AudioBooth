import Combine
import Foundation

extension UserPreferences {
  private static let syncableKeys: [String] = [
    "homeSections",
    "autoDownloadBooks",
    "removeDownloadOnCompletion",
    "skipForwardInterval",
    "skipBackwardInterval",
    "smartRewindInterval",
    "smartRewindOnInterruptionInterval",
    "shakeSensitivity",
    "customTimerMinutes",
    "timerFadeOut",
    "lockScreenNextPreviousUsesChapters",
    "lockScreenAllowPlaybackPositionChange",
    "timeRemainingAdjustsWithSpeed",
    "chapterProgressionAdjustsWithSpeed",
    "showFullBookDuration",
    "showBookProgressBar",
    "hideChapterSkipButtons",
    "volumeLevel",
    "libraryDisplayMode",
    "collapseSeriesInLibrary",
    "groupSeriesInOffline",
    "librarySortBy",
    "librarySortAscending",
    "libraryFilter",
    "showNFCTagWriting",
    "iCloudSyncEnabled",
    "accentColor",
    "autoTimerMode",
    "autoTimerWindowStart",
    "autoTimerWindowEnd",
    "playerOrientation",
    "colorScheme",
    "continueSectionSize",
    "ebookReader.fontSize",
    "ebookReader.fontWeight",
    "ebookReader.textNormalization",
    "ebookReader.fontFamily",
    "ebookReader.theme",
    "ebookReader.pageMargins",
    "ebookReader.scroll",
    "ebookReader.tapToNavigate",
    "ebookReader.publisherStyles",
    "ebookReader.lineHeight",
    "ebookReader.paragraphIndent",
    "ebookReader.paragraphSpacing",
    "ebookReader.wordSpacing",
    "ebookReader.letterSpacing",
    "authorsPageSortOrder",
    "podcastEpisodeFilter",
    "podcastEpisodeSort",
    "podcastEpisodeSortAscending",
  ]

  func setupCloudSync() {
    cloudObserver = NotificationCenter.default.addObserver(
      forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: cloud,
      queue: .main
    ) { [weak self] notification in
      self?.handleCloudChange(notification)
    }

    localObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.syncToCloud()
    }

    if iCloudSyncEnabled {
      cloud.synchronize()
      syncFromCloud()
    }
  }

  private func handleCloudChange(_ notification: Notification) {
    guard iCloudSyncEnabled else { return }

    guard let userInfo = notification.userInfo,
      let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
    else { return }

    if changeReason == NSUbiquitousKeyValueStoreServerChange
      || changeReason == NSUbiquitousKeyValueStoreInitialSyncChange
    {
      syncFromCloud()
    }
  }

  private func syncFromCloud() {
    guard iCloudSyncEnabled else { return }

    isApplyingCloudChanges = true
    defer { isApplyingCloudChanges = false }

    for key in Self.syncableKeys {
      guard let cloudValue = cloud.object(forKey: key) else { continue }
      UserDefaults.standard.set(cloudValue, forKey: key)
    }

    objectWillChange.send()
  }

  func syncToCloud() {
    guard iCloudSyncEnabled, !isApplyingCloudChanges else { return }

    for key in Self.syncableKeys {
      if let value = UserDefaults.standard.object(forKey: key) {
        cloud.set(value, forKey: key)
      }
    }

    cloud.synchronize()
  }

  func purgeCloud() {
    for key in Self.syncableKeys {
      cloud.removeObject(forKey: key)
    }

    cloud.synchronize()
  }
}
