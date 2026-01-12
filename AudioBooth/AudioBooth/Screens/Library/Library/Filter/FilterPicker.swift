import API
import Combine
import SwiftUI

struct FilterPicker: View {
  @ObservedObject var model: Model
  @Environment(\.dismiss) private var dismiss
  @State private var expandedSection: FilterCategory?

  var body: some View {
    List {
      Section {
        FilterRow(
          title: "All",
          isSelected: model.selectedFilter == nil,
          action: {
            model.selectedFilter = nil
            dismiss()
          }
        )
      }

      if !model.progressOptions.isEmpty {
        CollapsibleSection(
          title: "Progress",
          isExpanded: expandedSection == .progress,
          isActive: isCategoryActive(.progress),
          toggle: { toggleSection(.progress) }
        ) {
          ForEach(model.progressOptions, id: \.self) { option in
            FilterRow(
              title: option,
              isSelected: isSelected(.progress(option)),
              action: {
                model.selectedFilter = .progress(option)
                dismiss()
              }
            )
          }
        }
      }

      if !model.authors.isEmpty {
        CollapsibleSection(
          title: "Authors",
          isExpanded: expandedSection == .authors,
          isActive: isCategoryActive(.authors),
          toggle: { toggleSection(.authors) }
        ) {
          ForEach(model.authors) { author in
            FilterRow(
              title: author.name,
              isSelected: isSelected(.authors(author.id, author.name)),
              action: {
                model.selectedFilter = .authors(author.id, author.name)
                dismiss()
              }
            )
          }
        }
      }

      if !model.genres.isEmpty {
        CollapsibleSection(
          title: "Genres",
          isExpanded: expandedSection == .genres,
          isActive: isCategoryActive(.genres),
          toggle: { toggleSection(.genres) }
        ) {
          ForEach(model.genres, id: \.self) { genre in
            FilterRow(
              title: genre,
              isSelected: isSelected(.genres(genre)),
              action: {
                model.selectedFilter = .genres(genre)
                dismiss()
              }
            )
          }
        }
      }

      if !model.narrators.isEmpty {
        CollapsibleSection(
          title: "Narrators",
          isExpanded: expandedSection == .narrators,
          isActive: isCategoryActive(.narrators),
          toggle: { toggleSection(.narrators) }
        ) {
          ForEach(model.narrators, id: \.self) { narrator in
            FilterRow(
              title: narrator,
              isSelected: isSelected(.narrators(narrator)),
              action: {
                model.selectedFilter = .narrators(narrator)
                dismiss()
              }
            )
          }
        }
      }

      if !model.series.isEmpty {
        CollapsibleSection(
          title: "Series",
          isExpanded: expandedSection == .series,
          isActive: isCategoryActive(.series),
          toggle: { toggleSection(.series) }
        ) {
          ForEach(model.series) { series in
            FilterRow(
              title: series.name,
              isSelected: isSelected(.series(series.id, series.name)),
              action: {
                model.selectedFilter = .series(series.id, series.name)
                dismiss()
              }
            )
          }
        }
      }

      if !model.tags.isEmpty {
        CollapsibleSection(
          title: "Tags",
          isExpanded: expandedSection == .tags,
          isActive: isCategoryActive(.tags),
          toggle: { toggleSection(.tags) }
        ) {
          ForEach(model.tags, id: \.self) { tag in
            FilterRow(
              title: tag,
              isSelected: isSelected(.tags(tag)),
              action: {
                model.selectedFilter = .tags(tag)
                dismiss()
              }
            )
          }
        }
      }

      if !model.languages.isEmpty {
        CollapsibleSection(
          title: "Languages",
          isExpanded: expandedSection == .languages,
          isActive: isCategoryActive(.languages),
          toggle: { toggleSection(.languages) }
        ) {
          ForEach(model.languages, id: \.self) { language in
            FilterRow(
              title: language,
              isSelected: isSelected(.languages(language)),
              action: {
                model.selectedFilter = .languages(language)
                dismiss()
              }
            )
          }
        }
      }

      if !model.publishers.isEmpty {
        CollapsibleSection(
          title: "Publishers",
          isExpanded: expandedSection == .publishers,
          isActive: isCategoryActive(.publishers),
          toggle: { toggleSection(.publishers) }
        ) {
          ForEach(model.publishers, id: \.self) { publisher in
            FilterRow(
              title: publisher,
              isSelected: isSelected(.publishers(publisher)),
              action: {
                model.selectedFilter = .publishers(publisher)
                dismiss()
              }
            )
          }
        }
      }

      if !model.publishedDecades.isEmpty {
        CollapsibleSection(
          title: "Published Decades",
          isExpanded: expandedSection == .publishedDecades,
          isActive: isCategoryActive(.publishedDecades),
          toggle: { toggleSection(.publishedDecades) }
        ) {
          ForEach(model.publishedDecades, id: \.self) { decade in
            FilterRow(
              title: decade,
              isSelected: isSelected(.publishedDecades(decade)),
              action: {
                model.selectedFilter = .publishedDecades(decade)
                dismiss()
              }
            )
          }
        }
      }
    }
    .navigationTitle("Filter Library")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Done") {
          dismiss()
        }
      }
    }
  }

  func isSelected(_ filter: LibraryPageModel.Filter) -> Bool {
    model.selectedFilter == filter
  }

  func isCategoryActive(_ category: FilterCategory) -> Bool {
    guard let selectedFilter = model.selectedFilter else { return false }

    switch (category, selectedFilter) {
    case (.progress, .progress): return true
    case (.authors, .authors): return true
    case (.genres, .genres): return true
    case (.narrators, .narrators): return true
    case (.series, .series): return true
    case (.tags, .tags): return true
    case (.languages, .languages): return true
    case (.publishers, .publishers): return true
    case (.publishedDecades, .publishedDecades): return true
    default: return false
    }
  }

  func toggleSection(_ category: FilterCategory) {
    if expandedSection == category {
      expandedSection = nil
    } else {
      expandedSection = category
    }
  }
}

extension FilterPicker {
  struct CollapsibleSection<Content: View>: View {
    let title: String
    let isExpanded: Bool
    let isActive: Bool
    let toggle: () -> Void
    let content: () -> Content

    var body: some View {
      Section {
        if isExpanded {
          content()
        }
      } header: {
        Button(action: toggle) {
          HStack {
            Text(title)
            Spacer()
            if isActive {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
            }
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  struct FilterRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        HStack {
          Text(title)
            .foregroundStyle(.primary)
          Spacer()
          if isSelected {
            Image(systemName: "checkmark")
              .foregroundStyle(.tint)
          }
        }
      }
    }
  }
}

enum FilterCategory: Hashable {
  case progress
  case authors
  case genres
  case narrators
  case series
  case tags
  case languages
  case publishers
  case publishedDecades
}

extension FilterPicker {
  @Observable
  class Model: ObservableObject {
    var progressOptions: [String]
    var authors: [FilterData.Author]
    var genres: [String]
    var narrators: [String]
    var series: [FilterData.Series]
    var tags: [String]
    var languages: [String]
    var publishers: [String]
    var publishedDecades: [String]

    var selectedFilter: LibraryPageModel.Filter? {
      didSet {
        onFilterChanged()
      }
    }

    func onFilterChanged() {}

    init(
      progressOptions: [String] = [],
      authors: [FilterData.Author] = [],
      genres: [String] = [],
      narrators: [String] = [],
      series: [FilterData.Series] = [],
      tags: [String] = [],
      languages: [String] = [],
      publishers: [String] = [],
      publishedDecades: [String] = [],
      selectedFilter: LibraryPageModel.Filter? = nil
    ) {
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
