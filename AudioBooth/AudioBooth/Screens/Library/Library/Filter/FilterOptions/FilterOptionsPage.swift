import API
import Combine
import SwiftUI

struct FilterOptionsPage: View {
  @ObservedObject var model: FilterPicker.Model
  let category: FilterCategory
  let onSelect: () -> Void

  @Environment(\.appTheme) private var theme
  @State private var searchText = ""

  var body: some View {
    if allOptions.count > 10 {
      content.searchable(text: $searchText, prompt: Text("Search"))
    } else {
      content
    }
  }

  private var content: some View {
    List {
      ForEach(visibleOptions) { option in
        Button {
          model.onFilterChanged(option.filter)
          onSelect()
        } label: {
          HStack {
            Text(verbatim: option.title)
              .foregroundStyle(.primary)
            Spacer()
            if model.selectedFilter == option.filter {
              Image(systemName: "checkmark")
                .foregroundStyle(.tint)
            }
          }
        }
        .listRowBackground(theme.colors.background.card)
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .overlay {
      if visibleOptions.isEmpty, !searchText.isEmpty {
        ContentUnavailableView.search(text: searchText)
      }
    }
    .navigationTitle(Text(verbatim: category.title))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var allOptions: [FilterPicker.FilterOption] {
    model.options(for: category)
  }

  private var visibleOptions: [FilterPicker.FilterOption] {
    let query = searchText.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return allOptions }
    return allOptions.filter { $0.title.localizedCaseInsensitiveContains(query) }
  }
}

#Preview("FilterOptionsPage") {
  NavigationStack {
    FilterOptionsPage(
      model: .init(
        source: .library,
        genres: ["Fantasy", "Science Fiction", "Mystery", "Thriller"],
        selectedFilter: .genres("Mystery")
      ),
      category: .genres,
      onSelect: {}
    )
  }
}
