import API
import Foundation
import Logging

final class FilterPickerModel: FilterPicker.Model {
  private let audiobookshelf = Audiobookshelf.shared

  init(currentFilter: LibraryPageModel.Filter?) {
    super.init(
      progressOptions: ["Finished", "In Progress", "Not Started", "Not Finished"],
      selectedFilter: currentFilter
    )

    if let cached = audiobookshelf.libraries.getCachedFilterData() {
      applyFilterData(cached)
    }
  }

  override func onFilterChanged(_ filter: LibraryPageModel.Filter?) {
    selectedFilter = filter
    UserPreferences.shared.libraryFilter = filter ?? .all
  }

  override func refresh() async {
    await fetchFilterData()
  }

  private func fetchFilterData() async {
    do {
      let data = try await audiobookshelf.libraries.fetchFilterData()
      applyFilterData(data)
    } catch {
      AppLogger.viewModel.error("Failed to fetch filter data: \(error)")
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
