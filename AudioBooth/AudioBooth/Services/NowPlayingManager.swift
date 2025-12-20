import API
import Foundation
import Logging
import MediaPlayer
import Nuke

final class NowPlayingManager {
  private var info: [String: Any] = [:]
  private let id: String
  private let title: String
  private let author: String?
  private var artwork: MPMediaItemArtwork?

  init(
    id: String,
    title: String,
    author: String?,
    coverURL: URL?,
    current: TimeInterval,
    duration: TimeInterval
  ) {
    self.id = id
    self.title = title
    self.author = author

    info[MPNowPlayingInfoPropertyExternalContentIdentifier] = id
    info[MPNowPlayingInfoPropertyExternalUserProfileIdentifier] = Audiobookshelf.shared.authentication.server?.id

    info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
    info[MPMediaItemPropertyTitle] = title
    info[MPMediaItemPropertyArtist] = author

    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = current
    info[MPMediaItemPropertyPlaybackDuration] = duration

    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0

    MPNowPlayingInfoCenter.default().playbackState = .interrupted

    update()

    if let coverURL {
      loadArtwork(from: coverURL)
    }
  }

  func update(chapter: String, current: TimeInterval, duration: TimeInterval) {
    info[MPMediaItemPropertyTitle] = chapter
    info[MPMediaItemPropertyArtist] = title
    info[MPMediaItemPropertyArtwork] = artwork

    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = current

    update()
  }

  func update(current: TimeInterval) {
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = current

    update()
  }

  func update(speed: Float) {
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(speed)
    info[MPNowPlayingInfoPropertyPlaybackRate] = Double(speed)

    update()
  }

  func update(rate: Float, current: TimeInterval) {
    info[MPNowPlayingInfoPropertyPlaybackRate] = Double(rate)
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = current

    update()

    MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
  }

  func clear() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  func update() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func loadArtwork(from url: URL) {
    Task {
      do {
        let request = ImageRequest(url: url)
        let image = try await ImagePipeline.shared.image(for: request)

        artwork = MPMediaItemArtwork(
          boundsSize: image.size,
          requestHandler: { _ in image }
        )

        info[MPMediaItemPropertyArtwork] = artwork
        update()
      } catch {
        AppLogger.player.error("Failed to load cover image for now playing: \(error)")
      }
    }
  }
}
