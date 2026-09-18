import Foundation

public final class ProgressService {
  private let audiobookshelf: Audiobookshelf

  init(audiobookshelf: Audiobookshelf) {
    self.audiobookshelf = audiobookshelf
  }

  public func fetch(bookID: String) async throws -> User.MediaProgress {
    let request = NetworkRequest<User.MediaProgress>(
      path: "/api/me/progress/\(bookID)",
      method: .get
    )

    return try await send(request, failure: "Failed to fetch media progress")
  }

  public func update(
    bookID: String,
    currentTime: TimeInterval? = nil,
    duration: TimeInterval? = nil,
    ebookProgress: Double? = nil,
    ebookLocation: String? = nil,
    isFinished: Bool? = nil
  ) async throws {
    var progress: Double?
    if let currentTime, let duration, duration > 0 {
      progress = min(1, max(0, currentTime / duration))
    }

    let request = NetworkRequest<Data>(
      path: "/api/me/progress/\(bookID)",
      method: .patch,
      body: ProgressUpdate(
        currentTime: currentTime,
        duration: duration,
        progress: progress,
        ebookProgress: ebookProgress,
        ebookLocation: ebookLocation,
        isFinished: isFinished ?? progress.map { $0 >= 1 }
      )
    )

    _ = try await send(request, failure: "Failed to update book progress")
  }

  public func markAsFinished(bookID: String) async throws {
    try await update(bookID: bookID, isFinished: true)
  }

  public func reset(progressID: String) async throws {
    let request = NetworkRequest<Data>(
      path: "/api/me/progress/\(progressID)",
      method: .delete
    )

    _ = try await send(request, failure: "Failed to reset book progress")
  }

  public func removeFromContinueListening(_ progressID: String) async throws {
    struct Response: Codable {}

    let request = NetworkRequest<Response>(
      path: "/api/me/progress/\(progressID)/remove-from-continue-listening",
      method: .get
    )

    _ = try await send(request, failure: "Failed to remove from continue listening")
  }

  private struct ProgressUpdate: Encodable {
    let currentTime: TimeInterval?
    let duration: TimeInterval?
    let progress: Double?
    let ebookProgress: Double?
    let ebookLocation: String?
    let isFinished: Bool?
  }

  private func send<T: Decodable>(_ request: NetworkRequest<T>, failure: String) async throws -> T {
    guard let networkService = audiobookshelf.networkService else {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "Network service not configured. Please login first."
      )
    }

    do {
      return try await networkService.send(request).value
    } catch {
      throw Audiobookshelf.AudiobookshelfError.networkError(
        "\(failure): \(error.localizedDescription)"
      )
    }
  }
}
