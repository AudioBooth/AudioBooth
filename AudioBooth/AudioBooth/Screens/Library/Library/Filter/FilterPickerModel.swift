import API
import Foundation

final class FilterPickerModel: FilterPicker.Model {
  private let audiobookshelf = Audiobookshelf.shared

  init(currentFilter: LibraryPageModel.Filter?) {
    super.init(
      progressOptions: ["Finished", "In Progress", "Not Started", "Not Finished"],
      selectedFilter: currentFilter
    )

    Task {
      await fetchFilterData()
    }
  }

  override func onFilterChanged() {
    Task { @MainActor in
      if let selectedFilter {
        UserPreferences.shared.libraryFilter = selectedFilter
      } else {
        UserPreferences.shared.libraryFilter = .all
      }
    }
  }

  override func refresh() async {
    await fetchFilterData()
  }

  private func fetchFilterData() async {
    if let cached = audiobookshelf.libraries.getCachedFilterData() {
      applyFilterData(cached)
    }

    do {
      let data = try await audiobookshelf.libraries.fetchFilterData()
      applyFilterData(data)
    } catch {
      print("Failed to fetch filter data: \(error)")
    }
  }

  private func applyFilterData(_ data: FilterData) {
    authors = data.authors
    genres = data.genres.sorted()
    narrators = data.narrators.sorted()
    series = data.series
    tags = data.tags.sorted()
    languages = data.languages.sorted()
    publishers = data.publishers.sorted()
    publishedDecades = data.publishedDecades.sorted(by: >)
  }
}
