import API
import Logging
import SwiftUI

final class NarratorsPageModel: NarratorsPage.Model {
  private let audiobookshelf = Audiobookshelf.shared

  init() {
    super.init()
    self.searchViewModel = SearchViewModel()
  }

  override func onAppear() {
    Task {
      await loadNarrators()
    }
  }

  override func refresh() async {
    await loadNarrators()
  }

  private func loadNarrators() async {
    isLoading = true

    do {
      let response = try await audiobookshelf.narrators.fetch()

      let narratorCards = response.map { narrator in
        NarratorCardModel(narrator: narrator)
      }

      self.narrators = narratorCards
    } catch {
      AppLogger.viewModel.error("Failed to fetch narrators: \(error)")
      narrators = []
    }

    isLoading = false
  }
}
