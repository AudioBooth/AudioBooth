import API
import Combine
import SwiftUI

struct FilterCategorySelectorSheet: View {
  @Environment(\.dismiss) var dismiss

  @ObservedObject var model: Model

  var body: some View {
    NavigationStack {
      List {
        if !model.progressOptions.isEmpty {
          Picker("Progress", selection: $model.selectedProgress) {
            Text("None").tag(nil as String?)
            ForEach(model.progressOptions, id: \.self) { option in
              Text(option).tag(option as String?)
            }
          }
          .onChange(of: model.selectedProgress) { _, _ in
            model.onFilterChanged()
          }
        }

        if !model.authors.isEmpty {
          Picker("Authors", selection: $model.selectedAuthor) {
            Text("None").tag(nil as FilterData.Author?)
            ForEach(model.authors) { author in
              Text(author.name).tag(author as FilterData.Author?)
            }
          }
          .onChange(of: model.selectedAuthor) { _, _ in
            model.onFilterChanged()
          }
        }

        if !model.genres.isEmpty {
          Picker("Genres", selection: $model.selectedGenre) {
            Text("None").tag(nil as String?)
            ForEach(model.genres, id: \.self) { genre in
              Text(genre).tag(genre as String?)
            }
          }
          .onChange(of: model.selectedGenre) { _, _ in
            model.onFilterChanged()
          }
        }

        if !model.narrators.isEmpty {
          Picker("Narrators", selection: $model.selectedNarrator) {
            Text("None").tag(nil as String?)
            ForEach(model.narrators, id: \.self) { narrator in
              Text(narrator).tag(narrator as String?)
            }
          }
          .onChange(of: model.selectedNarrator) { _, _ in
            model.onFilterChanged()
          }
        }

        if !model.series.isEmpty {
          Picker("Series", selection: $model.selectedSeries) {
            Text("None").tag(nil as FilterData.Series?)
            ForEach(model.series) { series in
              Text(series.name).tag(series as FilterData.Series?)
            }
          }
          .onChange(of: model.selectedSeries) { _, _ in
            model.onFilterChanged()
          }
        }

        if !model.tags.isEmpty {
          Picker("Tags", selection: $model.selectedTag) {
            Text("None").tag(nil as String?)
            ForEach(model.tags, id: \.self) { tag in
              Text(tag).tag(tag as String?)
            }
          }
          .onChange(of: model.selectedTag) { _, _ in
            model.onFilterChanged()
          }
        }

        if !model.languages.isEmpty {
          Picker("Languages", selection: $model.selectedLanguage) {
            Text("None").tag(nil as String?)
            ForEach(model.languages, id: \.self) { language in
              Text(language).tag(language as String?)
            }
          }
          .onChange(of: model.selectedLanguage) { _, _ in
            model.onFilterChanged()
          }
        }

        if !model.publishers.isEmpty {
          Picker("Publishers", selection: $model.selectedPublisher) {
            Text("None").tag(nil as String?)
            ForEach(model.publishers, id: \.self) { publisher in
              Text(publisher).tag(publisher as String?)
            }
          }
          .onChange(of: model.selectedPublisher) { _, _ in
            model.onFilterChanged()
          }
        }

        if !model.publishedDecades.isEmpty {
          Picker("Published Decades", selection: $model.selectedDecade) {
            Text("None").tag(nil as String?)
            ForEach(model.publishedDecades, id: \.self) { decade in
              Text(decade).tag(decade as String?)
            }
          }
          .onChange(of: model.selectedDecade) { _, _ in
            model.onFilterChanged()
          }
        }
      }
      .navigationTitle("Filter Library")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .tint(.primary)
        }
      }
    }
  }
}

extension FilterCategorySelectorSheet {
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

    var selectedFilter: LibraryPageModel.Filter?

    var selectedProgress: String? {
      get {
        if case .progress(let name) = selectedFilter {
          return name
        }
        return nil
      }
      set {
        selectedFilter = newValue.map { .progress($0) }
      }
    }

    var selectedAuthor: FilterData.Author? {
      get {
        if case .authors(let id, let name) = selectedFilter {
          return FilterData.Author(id: id, name: name)
        }
        return nil
      }
      set {
        selectedFilter = newValue.map { .authors($0.id, $0.name) }
      }
    }

    var selectedGenre: String? {
      get {
        if case .genres(let name) = selectedFilter {
          return name
        }
        return nil
      }
      set {
        selectedFilter = newValue.map { .genres($0) }
      }
    }

    var selectedNarrator: String? {
      get {
        if case .narrators(let name) = selectedFilter {
          return name
        }
        return nil
      }
      set {
        selectedFilter = newValue.map { .narrators($0) }
      }
    }

    var selectedSeries: FilterData.Series? {
      get {
        if case .series(let id, let name) = selectedFilter {
          return FilterData.Series(id: id, name: name)
        }
        return nil
      }
      set {
        selectedFilter = newValue.map { .series($0.id, $0.name) }
      }
    }

    var selectedTag: String? {
      get {
        if case .tags(let name) = selectedFilter {
          return name
        }
        return nil
      }
      set {
        selectedFilter = newValue.map { .tags($0) }
      }
    }

    var selectedLanguage: String? {
      get {
        if case .languages(let name) = selectedFilter {
          return name
        }
        return nil
      }
      set {
        selectedFilter = newValue.map { .languages($0) }
      }
    }

    var selectedPublisher: String? {
      get {
        if case .publishers(let name) = selectedFilter {
          return name
        }
        return nil
      }
      set {
        selectedFilter = newValue.map { .publishers($0) }
      }
    }

    var selectedDecade: String? {
      get {
        if case .publishedDecades(let decade) = selectedFilter {
          return decade
        }
        return nil
      }
      set {
        selectedFilter = newValue.map { .publishedDecades($0) }
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

#Preview("FilterCategorySelectorSheet") {
  FilterCategorySelectorSheet(
    model: .init(
      progressOptions: ["Finished", "In Progress", "Not Started", "Not Finished"],
      authors: [
        FilterData.Author(id: "1", name: "Brandon Sanderson"),
        FilterData.Author(id: "2", name: "J.K. Rowling"),
      ],
      genres: ["Fantasy", "Science Fiction", "Mystery"]
    )
  )
}
