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
    guard narrators.isEmpty else { return }
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

  override func onLetterTapped(_ letter: String) {
    let availableSections = Set(narrators.map { sectionLetter(for: $0.name) })

    if availableSections.contains(letter) {
      scrollTarget = letter
    } else if let nextLetter = findNextAvailableLetter(after: letter, in: availableSections) {
      scrollTarget = .init(nextLetter)
    }
  }
}

extension NarratorsPageModel {
  private func findNextAvailableLetter(after letter: String, in sections: Set<String>) -> String? {
    if letter == "#" { return AuthorsPage.bottomScrollID }
    let sortedSections = sections.filter { $0 != "#" }.sorted()
    if let next = sortedSections.first(where: { $0 > letter }) {
      return next
    }
    return sections.contains("#") ? "#" : NarratorsPage.bottomScrollID
  }

  private func sectionLetter(for name: String) -> String {
    guard let firstChar = name.uppercased().first else { return "#" }
    let validLetters: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    return validLetters.contains(firstChar) ? String(firstChar) : "#"
  }
}
