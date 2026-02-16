import Combine
import Models
import SwiftUI

final class PodcastEpisodeDetailViewModel: PodcastEpisodeDetailView.Model {
  private let podcastID: String
  private let episodeID: String
  private let podcastModel: PodcastDetailsView.Model
  private let episodeData: PodcastDetailsView.Model.Episode
  private let playerManager = PlayerManager.shared
  private var cancellables = Set<AnyCancellable>()

  init(podcastModel: PodcastDetailsView.Model, episode: PodcastDetailsView.Model.Episode) {
    self.podcastID = podcastModel.podcastID
    self.episodeID = episode.id
    self.podcastModel = podcastModel
    self.episodeData = episode

    super.init(episode: episode)

    observePlayer()
  }

  override func onPlay() {
    podcastModel.onPlayEpisode(episodeData)
  }

  private func observePlayer() {
    playerManager.$current
      .sink { [weak self] current in
        guard let self else { return }
        observeIsPlaying(current)
      }
      .store(in: &cancellables)
  }

  private func observeIsPlaying(_ current: BookPlayer.Model?) {
    guard let current, current.podcastID == podcastID, current.id == episodeID else {
      isPlaying = false
      return
    }

    isPlaying = current.isPlaying

    withObservationTracking {
      _ = current.isPlaying
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.updatePlayingState()
        self.observeIsPlaying(self.playerManager.current)
      }
    }
  }

  private func updatePlayingState() {
    let current = playerManager.current
    if current?.podcastID == podcastID, current?.id == episodeID {
      isPlaying = current?.isPlaying ?? false
    } else {
      isPlaying = false
    }
  }
}
