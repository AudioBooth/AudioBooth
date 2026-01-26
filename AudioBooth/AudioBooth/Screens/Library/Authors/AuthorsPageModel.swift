import API
import Logging
import SwiftUI

final class AuthorsPageModel: AuthorsPage.Model {
  private let audiobookshelf = Audiobookshelf.shared

  private var targetLetter: String?

  private var currentPage: Int = 0
  private var isLoadingNextPage: Bool = false
  private let itemsPerPage: Int = 100

  init() {
    super.init(
      isLoading: true,
      hasMorePages: true
    )
    self.searchViewModel = SearchViewModel()
  }

  override func onAppear() {
    guard authors.isEmpty else { return }
    Task {
      await loadAuthors()
    }
  }

  override func refresh() async {
    currentPage = 0
    hasMorePages = true
    authors.removeAll()
    await loadAuthors()
  }

  private func loadAuthors() async {
    guard hasMorePages && !isLoadingNextPage else { return }

    isLoadingNextPage = true
    isLoading = currentPage == 0

    do {
      let response = try await audiobookshelf.authors.fetch(
        limit: itemsPerPage,
        page: currentPage,
        sortBy: .name,
        ascending: true
      )

      let authorCards = response.results.map { author in
        AuthorCardModel(author: author)
      }

      authors.append(contentsOf: authorCards)
      currentPage += 1

      hasMorePages = (currentPage * itemsPerPage) < response.total

    } catch {
      AppLogger.viewModel.error("Failed to fetch authors: \(error)")
      if currentPage == 0 {
        authors = []
      }
    }

    isLoadingNextPage = false
    isLoading = false
    try? await Task.sleep(for: .milliseconds(500))
    checkTargetLetterAfterLoad()
  }

  override func loadNextPageIfNeeded() {
    Task {
      await loadAuthors()
    }
  }

  override func onLetterTapped(_ letter: String) {
    let availableSections = computeAvailableSections()

    if availableSections.contains(letter) {
      scrollTarget = .init(letter)
      targetLetter = nil
    } else if let nextLetter = findNextAvailableLetter(after: letter, in: availableSections) {
      scrollTarget = .init(nextLetter)
      targetLetter = nil
    } else if hasMorePages {
      targetLetter = letter
      scrollTarget = .init(AuthorsPage.bottomScrollID)
    }
  }
}

extension AuthorsPageModel {
  private func computeAvailableSections() -> Set<String> {
    Set(authors.map { sectionLetter(for: $0.name) })
  }

  private func sectionLetter(for name: String) -> String {
    guard let firstChar = name.uppercased().first else { return "#" }
    let validLetters: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    return validLetters.contains(firstChar) ? String(firstChar) : "#"
  }

  private func findNextAvailableLetter(after letter: String, in sections: Set<String>) -> String? {
    if letter == "#" { return AuthorsPage.bottomScrollID }
    let sortedSections = sections.filter { $0 != "#" }.sorted()
    if let next = sortedSections.first(where: { $0 > letter }) {
      return next
    }
    return sections.contains("#") ? "#" : AuthorsPage.bottomScrollID
  }

  private func checkTargetLetterAfterLoad() {
    guard let target = targetLetter else { return }

    let sections = computeAvailableSections()

    if sections.contains(target) {
      scrollTarget = .init(target)
      targetLetter = nil
      return
    }

    if let nextLetter = findNextAvailableLetter(after: target, in: sections) {
      scrollTarget = .init(nextLetter)
      targetLetter = nil
      return
    }

    if hasMorePages {
      scrollTarget = .init(AuthorsPage.bottomScrollID)
    } else {
      targetLetter = nil
    }
  }
}
