import API
import Logging
import SwiftUI

final class AuthorsPageModel: AuthorsPage.Model {
  private let audiobookshelf = Audiobookshelf.shared
  private var targetLetter: String?
  private var allAuthors: [AuthorCard.Model] = []

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
    guard sections.isEmpty else { return }
    Task {
      await loadAuthors()
    }
  }

  override func refresh() async {
    currentPage = 0
    hasMorePages = true
    allAuthors.removeAll()
    sections = []
    await loadAuthors()
  }

  private func loadAuthors() async {
    guard hasMorePages && !isLoadingNextPage else { return }

    isLoadingNextPage = true
    isLoading = currentPage == 0

    do {
      let preferences = UserPreferences.shared
      let response = try await audiobookshelf.authors.fetch(
        limit: itemsPerPage,
        page: currentPage,
        sortBy: preferences.authorsSortBy,
        ascending: preferences.authorsSortAscending
      )

      let authorCards = response.results.map { AuthorCardModel(author: $0) }

      allAuthors.append(contentsOf: authorCards)
      sections = buildSections(from: allAuthors)
      currentPage += 1

      hasMorePages = (currentPage * itemsPerPage) < response.total

    } catch {
      AppLogger.viewModel.error("Failed to fetch authors: \(error)")
      if currentPage == 0 {
        sections = []
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

  override func onSortOptionTapped(_ sortBy: AuthorsService.SortBy) {
    let preferences = UserPreferences.shared
    if preferences.authorsSortBy == sortBy {
      preferences.authorsSortAscending.toggle()
    } else {
      preferences.authorsSortBy = sortBy
      preferences.authorsSortAscending = true
    }
    Task { await refresh() }
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
  private func sectionLetter(for name: String) -> String {
    guard let firstChar = name.uppercased().first else { return "#" }
    let validLetters: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    return validLetters.contains(firstChar) ? String(firstChar) : "#"
  }

  private func buildSections(from authors: [AuthorCard.Model]) -> [AuthorsPage.AuthorSection] {
    let sortBy = UserPreferences.shared.authorsSortBy
    guard [.name, .lastFirst].contains(sortBy) else {
      return [AuthorsPage.AuthorSection(id: "all", letter: "", authors: authors)]
    }

    var sectionOrder: [String] = []
    var grouped: [String: [AuthorCard.Model]] = [:]

    for author in authors {
      let name = sortBy == .lastFirst ? author.lastFirst : author.name
      let letter = sectionLetter(for: name)
      if grouped[letter] == nil {
        sectionOrder.append(letter)
        grouped[letter] = []
      }
      grouped[letter]!.append(author)
    }

    return sectionOrder.map { letter in
      AuthorsPage.AuthorSection(id: letter, letter: letter, authors: grouped[letter]!)
    }
  }

  private func computeAvailableSections() -> Set<String> {
    Set(sections.map { $0.letter })
  }

  private func findNextAvailableLetter(after letter: String, in sections: Set<String>) -> String? {
    let ascending = UserPreferences.shared.authorsSortAscending
    let sortedSections = sections.filter { $0 != "#" }.sorted()

    if letter == "#" {
      return ascending ? AuthorsPage.bottomScrollID : sortedSections.last
    }

    if ascending {
      if let next = sortedSections.first(where: { $0 > letter }) {
        return next
      }
      return sections.contains("#") ? "#" : AuthorsPage.bottomScrollID
    } else {
      if let prev = sortedSections.last(where: { $0 < letter }) {
        return prev
      }
      return AuthorsPage.bottomScrollID
    }
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
