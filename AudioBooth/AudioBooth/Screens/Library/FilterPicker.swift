import API
import Combine
import SwiftUI

struct FilterPicker: View {
  @ObservedObject var model: Model

  var body: some View {
    Menu {
      Filter("All", isSelected: model.selectedFilter == nil) {
        model.selectedFilter = nil
      }

      if !model.progressOptions.isEmpty {
        Category("Progress", isSelected: isCategoryActive(.progress)) {
          ForEach(model.progressOptions, id: \.self) { option in
            Filter(option, isSelected: isSelected(.progress(option))) {
              model.selectedFilter = .progress(option)
            }
          }
        }
      }

      if !model.authors.isEmpty {
        Category("Authors", isSelected: isCategoryActive(.authors)) {
          ForEach(model.authors) { author in
            Filter(author.name, isSelected: isSelected(.authors(author.id, author.name))) {
              model.selectedFilter = .authors(author.id, author.name)
            }
          }
        }
      }

      if !model.genres.isEmpty {
        Category("Genres", isSelected: isCategoryActive(.genres)) {
          ForEach(model.genres, id: \.self) { genre in
            Filter(genre, isSelected: isSelected(.genres(genre))) {
              model.selectedFilter = .genres(genre)
            }
          }
        }
      }

      if !model.narrators.isEmpty {
        Category("Narrators", isSelected: isCategoryActive(.narrators)) {
          ForEach(model.narrators, id: \.self) { narrator in
            Filter(narrator, isSelected: isSelected(.narrators(narrator))) {
              model.selectedFilter = .narrators(narrator)
            }
          }
        }
      }

      if !model.series.isEmpty {
        Category("Series", isSelected: isCategoryActive(.series)) {
          ForEach(model.series) { series in
            Filter(series.name, isSelected: isSelected(.series(series.id, series.name))) {
              model.selectedFilter = .series(series.id, series.name)
            }
          }
        }
      }

      if !model.tags.isEmpty {
        Category("Tags", isSelected: isCategoryActive(.tags)) {
          ForEach(model.tags, id: \.self) { tag in
            Filter(tag, isSelected: isSelected(.tags(tag))) {
              model.selectedFilter = .tags(tag)
            }
          }
        }
      }

      if !model.languages.isEmpty {
        Category("Languages", isSelected: isCategoryActive(.languages)) {
          ForEach(model.languages, id: \.self) { language in
            Filter(language, isSelected: isSelected(.languages(language))) {
              model.selectedFilter = .languages(language)
            }
          }
        }
      }

      if !model.publishers.isEmpty {
        Category("Publishers", isSelected: isCategoryActive(.publishers)) {
          ForEach(model.publishers, id: \.self) { publisher in
            Filter(publisher, isSelected: isSelected(.publishers(publisher))) {
              model.selectedFilter = .publishers(publisher)
            }
          }
        }
      }

      if !model.publishedDecades.isEmpty {
        Category("Published Decades", isSelected: isCategoryActive(.publishedDecades)) {
          ForEach(model.publishedDecades, id: \.self) { decade in
            Filter(decade, isSelected: isSelected(.publishedDecades(decade))) {
              model.selectedFilter = .publishedDecades(decade)
            }
          }
        }
      }
    } label: {
      Label(
        filterButtonLabel ?? "All",
        systemImage: filterButtonLabel == nil
          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
      )
    }
  }
}

extension FilterPicker {
  var filterButtonLabel: String? {
    switch model.selectedFilter {
    case .all: nil
    case .progress(let name): name
    case .authors(_, let name): name
    case .series(_, let name): name
    case .narrators(let name): name
    case .genres(let name): name
    case .tags(let name): name
    case .languages(let name): name
    case .publishers(let name): name
    case .publishedDecades(let decade): decade
    case nil: nil
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
}

extension FilterPicker {
  struct Category<Content: View>: View {
    let title: String
    let isSelected: Bool
    let content: () -> Content

    init(_ title: String, isSelected: Bool, @ViewBuilder content: @escaping () -> Content) {
      self.title = title
      self.isSelected = isSelected
      self.content = content
    }

    var body: some View {
      Menu(
        content: content,
        label: {
          if isSelected {
            Image(systemName: "checkmark")
          }
          Text(title)
        }
      )
    }
  }

  struct Filter: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
      self.title = title
      self.isSelected = isSelected
      self.action = action
    }

    var body: some View {
      Button(
        action: action,
        label: {
          HStack {
            if isSelected {
              Image(systemName: "checkmark")
            }
            Text(title)
          }
        }
      )
    }
  }
}

enum FilterCategory {
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
