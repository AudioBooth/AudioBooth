import Foundation
import Logging
import Speech

@available(iOS 26.0, *)
nonisolated enum ReadAlongAvailability {
  enum Failure: LocalizedError {
    case deviceUnsupported
    case localeUnsupported(Locale)
    case modelInstallFailed(any Error)
    case modelStillDownloading
    case localeUnavailable(Locale)

    var errorDescription: String? {
      switch self {
      case .deviceUnsupported:
        String(localized: "Read Along isn't supported on this device.")
      case let .localeUnsupported(locale):
        String(localized: "Read Along doesn't support \(locale.displayName) yet.")
      case .modelInstallFailed:
        String(localized: "Couldn't download the speech model. Check your connection and try again.")
      case .modelStillDownloading:
        String(localized: "The speech model is still downloading. Try Read Along again in a moment.")
      case let .localeUnavailable(locale):
        String(localized: "Read Along couldn't reserve the \(locale.displayName) speech model.")
      }
    }
  }

  private static let progressPollInterval = Duration.milliseconds(250)

  static func prepare(
    preferred: Locale,
    onDownloadProgress: @Sendable @escaping (Double) -> Void = { _ in }
  ) async throws -> Locale {
    guard SpeechTranscriber.isAvailable else { throw Failure.deviceUnsupported }

    guard let locale = await supportedLocale(nearest: preferred) else {
      throw Failure.localeUnsupported(preferred)
    }

    let transcriber = makeTranscriber(locale: locale)

    switch await AssetInventory.status(forModules: [transcriber]) {
    case .installed:
      break
    case .unsupported:
      throw Failure.localeUnsupported(locale)
    case .supported, .downloading:
      try await install(transcriber, onProgress: onDownloadProgress)
    @unknown default:
      throw Failure.localeUnsupported(locale)
    }

    try await reserve(locale)
    return locale
  }

  private static func reserve(_ locale: Locale) async throws {
    guard await !AssetInventory.reservedLocales.contains(locale) else { return }

    do {
      guard try await AssetInventory.reserve(locale: locale) else {
        throw Failure.localeUnavailable(locale)
      }
    } catch {
      guard try await makeRoomForReservation(excluding: locale) else {
        throw Failure.localeUnavailable(locale)
      }
      guard try await AssetInventory.reserve(locale: locale) else {
        throw Failure.localeUnavailable(locale)
      }
    }

    AppLogger.readAlong.info("Reserved speech locale \(locale.identifier)")
  }

  private static func makeRoomForReservation(excluding locale: Locale) async throws -> Bool {
    let reserved = await AssetInventory.reservedLocales
    guard let evictable = reserved.first(where: { $0 != locale }) else { return false }
    return await AssetInventory.release(reservedLocale: evictable)
  }

  static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
    SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )
  }

  private static func install(
    _ transcriber: SpeechTranscriber,
    onProgress: @Sendable @escaping (Double) -> Void
  ) async throws {
    do {
      if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        let reporter = pollProgress(of: request, into: onProgress)
        defer { reporter.cancel() }

        try await withTaskCancellationHandler {
          try await request.downloadAndInstall()
        } onCancel: {
          reporter.cancel()
        }
        onProgress(1)
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw Failure.modelInstallFailed(error)
    }

    try Task.checkCancellation()

    guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
      throw Failure.modelStillDownloading
    }
  }

  private static func pollProgress(
    of request: AssetInstallationRequest,
    into onProgress: @Sendable @escaping (Double) -> Void
  ) -> Task<Void, Never> {
    let progress = request.progress
    return Task {
      while !Task.isCancelled {
        onProgress(progress.fractionCompleted)
        try? await Task.sleep(for: progressPollInterval)
      }
    }
  }

  private static func supportedLocale(nearest preferred: Locale) async -> Locale? {
    if let match = await SpeechTranscriber.supportedLocale(equivalentTo: preferred) {
      return match
    }
    return await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
  }
}

nonisolated private extension Locale {
  var displayName: String {
    localizedString(forIdentifier: identifier) ?? identifier
  }
}
