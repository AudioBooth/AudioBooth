import API
import Foundation
import Logging

final class FilterPickerModel: FilterPicker.Model {
  private let audiobookshelf = Audiobookshelf.shared

  var onFilterSelected: ((FilterPicker.Model.Filter?) -> Void)?

  init(currentFilter: FilterPicker.Model.Filter?, source: Source) {
    super.init(
      source: source,
      progressOptions: ["Finished", "In Progress", "Not Started", "Not Finished"],
      selectedFilter: currentFilter
    )

    if let cached = audiobookshelf.filterData.cached() {
      applyFilterData(cached)
    }
  }

  override func onFilterChanged(_ filter: FilterPicker.Model.Filter?) {
    selectedFilter = filter
    if source == .library {
      UserPreferences.shared.libraryFilter = filter ?? .all
    }
    onFilterSelected?(filter)
  }

  override func refresh() async {
    await fetchFilterData()
  }

  private func fetchFilterData() async {
    do {
      let data = try await audiobookshelf.filterData.fetch()
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
