import API
import AVFoundation
import Combine
import Foundation
import Logging
import MediaPlayer
import Models
import Nuke

final class NowPlayingManager {
  private var info: [String: Any]
  private let id: String
  private let title: String
  private let artist: String?
  private var artwork: MPMediaItemArtwork?
  private var animatedArtwork: Any?
  private let preferences = UserPreferences.shared
  private var playbackState: MPNowPlayingPlaybackState = .paused

  private weak var player: AudioPlayer?
  private var chapters: ChapterPickerSheet.Model?
  private var mediaProgress: MediaProgress?
  private var cancellables = Set<AnyCancellable>()

  init(
    id: String,
    title: String,
    author: String?,
    podcastTitle: String? = nil,
    coverURL: URL?,
    current: TimeInterval,
    duration: TimeInterval
  ) {
    self.info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

    self.id = id
    self.title = title
    self.artist = podcastTitle ?? author

    primeNowPlaying()

    info[MPNowPlayingInfoPropertyExternalContentIdentifier] = id
    info[MPNowPlayingInfoPropertyExternalUserProfileIdentifier] = Audiobookshelf.shared.authentication.server?.id

    info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
    info[MPMediaItemPropertyMediaType] = (podcastTitle != nil ? MPMediaType.podcast : .audioBook).rawValue
    info[MPMediaItemPropertyTitle] = title
    info[MPMediaItemPropertyArtist] = artist

    info[MPMediaItemPropertyPlaybackDuration] = duration
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = current

    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0

    if let coverURL {
      loadArtwork(from: coverURL)
    }
  }

  private func primeNowPlaying() {
    Task {
      guard !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else { return }

      AudioSession.configure()
      await AudioSession.activate()

      let url = URL(string: "data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=")!
      let player = AVPlayer(url: url)
      player.allowsExternalPlayback = false
      player.volume = 0
      player.play()
      try? await Task.sleep(for: .milliseconds(500))
    }
  }

  func configure(
    player: AudioPlayer,
    chapters: ChapterPickerSheet.Model?,
    mediaProgress: MediaProgress
  ) {
    self.player = player
    self.chapters = chapters
    self.mediaProgress = mediaProgress

    observeChapterChanges()
    observePreferenceChanges()

    player.events
      .sink { [weak self] event in
        switch event {
        case .seek, .rateChanged, .stateChanged:
          self?.update()
        default:
          break
        }
      }
      .store(in: &cancellables)

    update()
  }

  func clear() {
    cancellables.removeAll()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private func observeChapterChanges() {
    guard let chapters else { return }

    withObservationTracking {
      _ = chapters.current
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        self.update()
        self.observeChapterChanges()
      }
    }
  }

  private func observePreferenceChanges() {
    withObservationTracking {
      _ = preferences.showFullBookDuration
      _ = preferences.lockScreenImmersiveCover
      _ = preferences.lockScreenShowRemainingInTitle
      _ = preferences.timeRemainingAdjustsWithSpeed
    } onChange: { [weak self] in
      guard let self else { return }
      RunLoop.main.perform {
        self.update()
        self.observePreferenceChanges()
      }
    }
  }

  func update() {
    guard let player, let mediaProgress else { return }

    info[MPMediaItemPropertyArtwork] = artwork

    if #available(iOS 26.0, *) {
      if preferences.lockScreenImmersiveCover,
        let animatedArtwork = animatedArtwork as? MPMediaItemAnimatedArtwork
      {
        info[MPNowPlayingInfoProperty3x4AnimatedArtwork] = animatedArtwork
      } else {
        info[MPNowPlayingInfoProperty3x4AnimatedArtwork] = nil
      }
    }

    playbackState = player.isPlaying ? .playing : .paused
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = player.rate
    info[MPNowPlayingInfoPropertyPlaybackRate] = player.isPlaying ? player.rate : 0.0

    if !preferences.showFullBookDuration, let chapters, let current = chapters.current,
      chapters.chapters.count > 1
    {
      info[MPMediaItemPropertyTitle] = decoratedTitle(current.title)
      info[MPMediaItemPropertyArtist] = title
      info[MPMediaItemPropertyAlbumTitle] = artist
      info[MPMediaItemPropertyPlaybackDuration] = current.end - current.start
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = chapters.currentElapsedTime(
        currentTime: mediaProgress.currentTime
      )
      info[MPNowPlayingInfoPropertyExternalContentIdentifier] = "\(id)-\(current.id)"
    } else {
      info[MPMediaItemPropertyTitle] = decoratedTitle(title)
      info[MPMediaItemPropertyArtist] = artist
      info[MPMediaItemPropertyAlbumTitle] = nil
      info[MPMediaItemPropertyPlaybackDuration] = mediaProgress.duration
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = mediaProgress.currentTime
      info[MPNowPlayingInfoPropertyExternalContentIdentifier] = id
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().playbackState = playbackState
  }

  private func decoratedTitle(_ base: String) -> String {
    guard preferences.lockScreenShowRemainingInTitle, let mediaProgress else { return base }

    var remaining = mediaProgress.duration - mediaProgress.currentTime
    guard remaining > 0 else { return base }

    if let player, preferences.timeRemainingAdjustsWithSpeed, player.rate > 0 {
      remaining /= Double(player.rate)
    }

    return "\(base) (\(remaining.formattedTimeRemaining))"
  }
}

extension NowPlayingManager {
  nonisolated private static func aspectFitted(image: UIImage, into targetSize: CGSize) -> UIImage {
    guard targetSize.width > 0, targetSize.height > 0 else { return image }
    let scale = min(targetSize.width / image.size.width, targetSize.height / image.size.height)
    guard scale < 1 else { return image }
    let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: scaledSize, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: scaledSize))
    }
  }

  nonisolated private static func aspectFilled(image: UIImage, into targetSize: CGSize) -> UIImage {
    guard targetSize.width > 0, targetSize.height > 0 else { return image }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
      let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
      let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
      let origin = CGPoint(
        x: (targetSize.width - scaledSize.width) / 2,
        y: (targetSize.height - scaledSize.height) / 2
      )
      image.draw(in: CGRect(origin: origin, size: scaledSize))
    }
  }

  private func loadArtwork(from url: URL) {
    Task {
      do {
        let request = ImageRequest(url: url, processors: [], priority: .high)
        let image = try await ImagePipeline.shared.image(for: request)

        artwork = MPMediaItemArtwork(
          boundsSize: image.size,
          requestHandler: { @Sendable size in
            Self.aspectFitted(image: image, into: size)
          }
        )

        if #available(iOS 26.0, *) {
          animatedArtwork = MPMediaItemAnimatedArtwork(
            artworkID: "\(id)-\(url.absoluteString)",
            previewImageRequestHandler: { @Sendable size in
              Self.aspectFilled(image: image, into: size)
            },
            videoAssetFileURLRequestHandler: { @Sendable _ in
              nil
            }
          )
        }

        info[MPMediaItemPropertyArtwork] = artwork
        update()
      } catch {
        AppLogger.player.error("Failed to load cover image for now playing: \(error)")
      }
    }
  }
}
