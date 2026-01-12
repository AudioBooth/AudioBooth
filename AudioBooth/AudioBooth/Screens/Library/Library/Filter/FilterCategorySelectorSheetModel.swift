import API
import Foundation

final class FilterCategorySelectorSheetModel: FilterCategorySelectorSheet.Model {
  private let onFilterApplied: (LibraryPageModel.Filter) -> Void
  private let onFilterCleared: () -> Void

  init(
    filterData: FilterData,
    currentFilter: LibraryPageModel.Filter?,
    onFilterApplied: @escaping (LibraryPageModel.Filter) -> Void,
    onFilterCleared: @escaping () -> Void
  ) {
    self.onFilterApplied = onFilterApplied
    self.onFilterCleared = onFilterCleared

    super.init(
      progressOptions: ["Finished", "In Progress", "Not Started", "Not Finished"],
      authors: filterData.authors,
      genres: filterData.genres.sorted(),
      narrators: filterData.narrators.sorted(),
      series: filterData.series,
      tags: filterData.tags.sorted(),
      languages: filterData.languages.sorted(),
      publishers: filterData.publishers.sorted(),
      publishedDecades: filterData.publishedDecades.sorted(by: >),
      selectedFilter: currentFilter
    )
  }

  override func onFilterChanged() {
    if let selectedFilter {
      onFilterApplied(selectedFilter)
    } else {
      onFilterCleared()
    }
  }
}
