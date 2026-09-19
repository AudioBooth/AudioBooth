import API
import Combine
import SwiftUI

struct FilterPicker: View {
  @ObservedObject var model: Model
  @Environment(\.appTheme) private var theme
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    List {
      Section {
        Button {
          model.onFilterChanged(nil)
          dismiss()
        } label: {
          HStack {
            Text("All")
              .foregroundStyle(.primary)
            Spacer()
            if model.selectedFilter == nil {
              Image(systemName: "checkmark")
                .foregroundStyle(.tint)
            }
          }
        }
        .listRowBackground(theme.colors.background.card)
      }

      if !model.availableCategories.isEmpty {
        Section {
          ForEach(model.availableCategories) { category in
            NavigationLink {
              FilterOptionsPage(model: model, category: category, onSelect: { dismiss() })
            } label: {
              categoryRow(category)
            }
            .listRowBackground(theme.colors.background.card)
          }
        } header: {
          Text("Filter By")
        }
      }

      if model.source != .series {
        Section {
          attributeRow(title: String(localized: "Explicit"), filter: .explicit)

          if model.source == .library {
            attributeRow(title: String(localized: "Abridged"), filter: .abridged)
          }
        } header: {
          Text("Attributes")
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
    .listSectionSpacing(.compact)
    .navigationTitle("Filter Library")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close", systemImage: "xmark") {
          dismiss()
        }
        .tint(.primary)
      }
    }
  }

  private func categoryRow(_ category: FilterCategory) -> some View {
    HStack(spacing: 12) {
      Image(systemName: category.icon)
        .foregroundStyle(.tint)
        .frame(width: 24)

      Text(verbatim: category.title)

      Spacer(minLength: 12)

      if let selection = model.selectedTitle(for: category) {
        Text(verbatim: selection)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }

  private func attributeRow(title: String, filter: Model.Filter) -> some View {
    Button {
      model.onFilterChanged(filter)
      dismiss()
    } label: {
      HStack {
        Text(verbatim: title)
          .foregroundStyle(.primary)
        Spacer()
        if model.selectedFilter == filter {
          Image(systemName: "checkmark")
            .foregroundStyle(.tint)
        }
      }
    }
    .listRowBackground(theme.colors.background.card)
  }
}

enum FilterCategory: Hashable, Identifiable {
  case progress
  case authors
  case genres
  case narrators
  case series
  case tags
  case languages
  case publishers
  case publishedDecades
  case tracks
  case ebooks

  var id: Self { self }

  var title: String {
    switch self {
    case .progress: String(localized: "Progress")
    case .authors: String(localized: "Authors")
    case .genres: String(localized: "Genres")
    case .narrators: String(localized: "Narrators")
    case .series: String(localized: "Series")
    case .tags: String(localized: "Tags")
    case .languages: String(localized: "Languages")
    case .publishers: String(localized: "Publishers")
    case .publishedDecades: String(localized: "Published Decades")
    case .tracks: String(localized: "Tracks")
    case .ebooks: String(localized: "Ebooks")
    }
  }

  var icon: String {
    switch self {
    case .progress: "chart.bar.fill"
    case .authors: "person.2.fill"
    case .genres: "theatermasks.fill"
    case .narrators: "mic.fill"
    case .series: "books.vertical.fill"
    case .tags: "tag.fill"
    case .languages: "globe"
    case .publishers: "building.columns.fill"
    case .publishedDecades: "calendar"
    case .tracks: "waveform"
    case .ebooks: "book.fill"
    }
  }
}

extension FilterPicker {
  struct FilterOption: Identifiable {
    let id: String
    let title: String
    let filter: FilterPicker.Model.Filter
  }
}

extension FilterPicker {
  @Observable
  class Model: ObservableObject {
    enum Source {
      case library
      case podcasts
      case series
    }

    let source: Source

    var progressOptions: [String]
    var authors: [FilterData.Author]
    var genres: [String]
    var narrators: [String]
    var series: [FilterData.Series]
    var tags: [String]
    var languages: [String]
    var publishers: [String]
    var publishedDecades: [String]

    var selectedFilter: FilterPicker.Model.Filter?

    var availableCategories: [FilterCategory] {
      var categories: [FilterCategory] = []
      if !progressOptions.isEmpty { categories.append(.progress) }
      if !authors.isEmpty { categories.append(.authors) }
      if !genres.isEmpty { categories.append(.genres) }
      if !narrators.isEmpty { categories.append(.narrators) }
      if source == .library, !series.isEmpty { categories.append(.series) }
      if !tags.isEmpty { categories.append(.tags) }
      if !languages.isEmpty { categories.append(.languages) }
      if !publishers.isEmpty { categories.append(.publishers) }
      if source == .library, !publishedDecades.isEmpty { categories.append(.publishedDecades) }
      if source == .library { categories.append(contentsOf: [.tracks, .ebooks]) }
      return categories
    }

    var selectedCategory: FilterCategory? {
      guard let selectedFilter else { return nil }
      return switch selectedFilter {
      case .progress: .progress
      case .authors: .authors
      case .genres: .genres
      case .narrators: .narrators
      case .series: .series
      case .tags: .tags
      case .languages: .languages
      case .publishers: .publishers
      case .publishedDecades: .publishedDecades
      case .tracks: .tracks
      case .ebooks: .ebooks
      case .all, .explicit, .abridged: nil
      }
    }

    func options(for category: FilterCategory) -> [FilterPicker.FilterOption] {
      switch category {
      case .progress:
        progressOptions.map { .init(id: $0, title: $0, filter: .progress($0)) }
      case .authors:
        authors.map { .init(id: $0.id, title: $0.name, filter: .authors($0.id, $0.name)) }
      case .genres:
        genres.map { .init(id: $0, title: $0, filter: .genres($0)) }
      case .narrators:
        narrators.map { .init(id: $0, title: $0, filter: .narrators($0)) }
      case .series:
        series.map { .init(id: $0.id, title: $0.name, filter: .series($0.id, $0.name)) }
      case .tags:
        tags.map { .init(id: $0, title: $0, filter: .tags($0)) }
      case .languages:
        languages.map { .init(id: $0, title: $0, filter: .languages($0)) }
      case .publishers:
        publishers.map { .init(id: $0, title: $0, filter: .publishers($0)) }
      case .publishedDecades:
        publishedDecades.map { .init(id: $0, title: $0, filter: .publishedDecades($0)) }
      case .tracks:
        Filter.Tracks.allCases.map { .init(id: $0.rawValue, title: $0.title, filter: .tracks($0)) }
      case .ebooks:
        Filter.Ebooks.allCases.map { .init(id: $0.rawValue, title: $0.title, filter: .ebooks($0)) }
      }
    }

    func selectedTitle(for category: FilterCategory) -> String? {
      guard selectedCategory == category else { return nil }
      return selectedFilter?.title
    }

    func onFilterChanged(_ filter: FilterPicker.Model.Filter?) {}
    func refresh() async {}

    init(
      source: Source,
      progressOptions: [String] = [],
      authors: [FilterData.Author] = [],
      genres: [String] = [],
      narrators: [String] = [],
      series: [FilterData.Series] = [],
      tags: [String] = [],
      languages: [String] = [],
      publishers: [String] = [],
      publishedDecades: [String] = [],
      selectedFilter: FilterPicker.Model.Filter? = nil
    ) {
      self.source = source
      self.progressOptions = progressOptions
      self.authors = authors
      self.genres = genres
      self.narrators = narrators
      self.series = series
      self.tags = tags
      self.languages = languages
      self.publishers = publishers
      self.publishedDecades = publishedDecades
      self.selectedFilter = selectedFilter
    }
  }
}

#Preview("FilterPicker") {
  NavigationStack {
    FilterPicker(
      model: .init(
        source: .library,
        progressOptions: ["Finished", "In Progress", "Not Started", "Not Finished"],
        authors: [
          FilterData.Author(id: "1", name: "Brandon Sanderson"),
          FilterData.Author(id: "2", name: "J.K. Rowling"),
        ],
        genres: ["Fantasy", "Science Fiction", "Mystery"],
        narrators: ["Michael Kramer", "Kate Reading"],
        selectedFilter: .genres("Fantasy")
      )
    )
  }
}
