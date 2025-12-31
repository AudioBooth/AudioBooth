@preconcurrency import CarPlay
import Combine
import Foundation

final class CarPlayNowPlaying: NSObject {
  private let interfaceController: CPInterfaceController
  private var cancellables = Set<AnyCancellable>()
  private let chapters: CarPlayChapters

  let template: CPNowPlayingTemplate

  init(interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
    self.chapters = CarPlayChapters(interfaceController: interfaceController)
    template = CPNowPlayingTemplate.shared

    super.init()

    setupButtons()
    setupObserver()
  }

  private func setupButtons() {
    updateButtons()
  }

  private func updateButtons() {
    let hasChapters = PlayerManager.shared.current?.chapters?.chapters.isEmpty == false

    let previousChapterButton = CPNowPlayingImageButton(image: UIImage(systemName: "backward.end.fill")!) {
      [weak self] _ in
      self?.onPreviousChapterTapped()
    }

    let nextChapterButton = CPNowPlayingImageButton(image: UIImage(systemName: "forward.end.fill")!) { [weak self] _ in
      self?.onNextChapterTapped()
    }

    let playbackRateButton = CPNowPlayingPlaybackRateButton(handler: { [weak self] _ in
      self?.onPlaybackRateButtonTapped()
    })

    let chaptersButton = CPNowPlayingImageButton(image: UIImage(systemName: "list.bullet")!) { [weak self] _ in
      self?.onChaptersButtonTapped()
    }
    chaptersButton.isEnabled = hasChapters

    let buttons: [CPNowPlayingButton] = [
      previousChapterButton,
      playbackRateButton,
      chaptersButton,
      nextChapterButton,
    ]

    template.updateNowPlayingButtons(buttons)
  }

  private func setupObserver() {
    PlayerManager.shared.$current
      .sink { [weak self] current in
        guard let self else { return }

        if let current {
          self.observePlayerChanges(for: current)
        } else {
          self.hideNowPlaying()
        }
      }
      .store(in: &cancellables)
  }

  private func observePlayerChanges(for player: BookPlayer.Model) {
    withObservationTracking {
      _ = player.chapters
    } onChange: { [weak self, weak player] in
      Task { @MainActor [weak self, weak player] in
        guard let self, let player else { return }
        self.updateButtons()
        self.observePlayerChanges(for: player)

        if let chapters = player.chapters {
          self.observeChapterChanges(for: player, chapters: chapters)
        }
      }
    }

    updateButtons()
  }

  private func observeChapterChanges(for player: BookPlayer.Model, chapters: ChapterPickerSheet.Model) {
    withObservationTracking {
      _ = chapters.currentIndex
    } onChange: { [weak self, weak player, weak chapters] in
      Task { @MainActor [weak self, weak player, weak chapters] in
        guard let self, let player, let chapters else { return }
        self.updateButtons()
        self.observeChapterChanges(for: player, chapters: chapters)
      }
    }
  }

  func showNowPlaying() {
    guard !interfaceController.templates.isEmpty else { return }

    if !interfaceController.templates.contains(where: { $0 is CPNowPlayingTemplate }) {
      interfaceController.pushTemplate(template, animated: true, completion: nil)
    }
  }

  private func hideNowPlaying() {
    if interfaceController.templates.contains(where: { $0 is CPNowPlayingTemplate }) {
      interfaceController.popToRootTemplate(animated: true, completion: nil)
    }
  }

  private func onPreviousChapterTapped() {
    guard let current = PlayerManager.shared.current,
      let chapters = current.chapters
    else { return }

    chapters.onPreviousChapterTapped()
  }

  private func onNextChapterTapped() {
    guard let current = PlayerManager.shared.current,
      let chapters = current.chapters
    else { return }

    chapters.onNextChapterTapped()
  }

  private func onPlaybackRateButtonTapped() {
    guard let current = PlayerManager.shared.current else { return }

    let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    let currentSpeed = current.speed.playbackSpeed

    if let currentIndex = speeds.firstIndex(of: currentSpeed) {
      let nextIndex = (currentIndex + 1) % speeds.count
      current.speed.onSpeedChanged(speeds[nextIndex])
    } else {
      current.speed.onSpeedChanged(1.0)
    }
  }

  private func onChaptersButtonTapped() {
    guard let current = PlayerManager.shared.current else { return }
    chapters.show(for: current)
  }
}
