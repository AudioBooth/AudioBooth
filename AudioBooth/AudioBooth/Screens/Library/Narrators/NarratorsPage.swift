import Combine
import NukeUI
import SwiftUI

struct NarratorsPage: View {
  @StateObject var model: Model

  var body: some View {
    content
  }

  var content: some View {
    Group {
      if !model.searchViewModel.searchText.isEmpty {
        SearchView(model: model.searchViewModel)
      } else {
        if model.isLoading && model.narrators.isEmpty {
          ProgressView("Loading narrators...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.narrators.isEmpty && !model.isLoading {
          ContentUnavailableView(
            "No Narrators Found",
            systemImage: "mic",
            description: Text(
              "Your library appears to have no narrators or no library is selected."
            )
          )
        } else {
          narratorsRowContent
        }
      }
    }
    .navigationTitle("Narrators")
    .navigationBarTitleDisplayMode(.inline)
    .refreshable {
      await model.refresh()
    }
    .onAppear(perform: model.onAppear)
  }

  var narratorSections: [NarratorSection] {
    let sortedNarrators = model.narrators.sorted { $0.name < $1.name }

    let grouped = Dictionary(grouping: sortedNarrators) { narrator in
      String(narrator.name.prefix(1).uppercased())
    }

    return grouped.map { letter, narrators in
      NarratorSection(id: letter, letter: letter, narrators: narrators)
    }.sorted { $0.letter < $1.letter }
  }

  var narratorsRowContent: some View {
    ScrollViewReader { proxy in
      ScrollView {
        narratorsList
      }
      .overlay(alignment: .trailing) {
        AlphabetScrollBar(
          availableSections: Set(narratorSections.map(\.letter)),
          scrollProxy: proxy
        )
      }
      .scrollIndicators(.hidden)
    }
  }

  var narratorsList: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(narratorSections) { section in
        Section {
          ForEach(section.narrators, id: \.id) { narrator in
            narratorRow(for: narrator)
          }
        } header: {
          sectionHeader(for: section.letter)
        }
        .id(section.letter)
      }
    }
  }

  func narratorRow(for narrator: NarratorCard.Model) -> some View {
    NavigationLink(value: NavigationDestination.narrator(name: narrator.name)) {
      VStack(alignment: .leading, spacing: 2) {
        Text(narrator.name)
          .font(.body)
          .frame(maxWidth: .infinity, alignment: .leading)

        if narrator.bookCount > 0 {
          Text("\(narrator.bookCount) \(narrator.bookCount == 1 ? "book" : "books")")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
    .buttonStyle(.plain)
  }

  func sectionHeader(for letter: String) -> some View {
    Text(letter)
      .font(.headline)
      .foregroundColor(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal)
      .padding(.vertical, 8)
      .background(Color(uiColor: .systemBackground))
  }
}

extension NarratorsPage {
  struct NarratorSection: Identifiable {
    let id: String
    let letter: String
    let narrators: [NarratorCard.Model]
  }

  @Observable class Model: ObservableObject {
    var isLoading: Bool

    var narrators: [NarratorCard.Model]
    var searchViewModel: SearchView.Model = SearchView.Model()

    func onAppear() {}
    func refresh() async {}

    init(
      isLoading: Bool = false,
      narrators: [NarratorCard.Model] = []
    ) {
      self.isLoading = isLoading
      self.narrators = narrators
    }
  }
}

extension NarratorsPage.Model {
  static var mock: NarratorsPage.Model {
    let sampleNarrators: [NarratorCard.Model] = [
      NarratorCard.Model(
        name: "Stephen Fry",
        bookCount: 25,
        imageURL: URL(
          string:
            "https://upload.wikimedia.org/wikipedia/commons/thumb/9/96/Stephen_Fry_2013.jpg/220px-Stephen_Fry_2013.jpg"
        )
      ),
      NarratorCard.Model(
        name: "Simon Vance",
        bookCount: 18,
        imageURL: nil
      ),
      NarratorCard.Model(
        name: "Kate Reading",
        bookCount: 12,
        imageURL: nil
      ),
    ]

    return NarratorsPage.Model(narrators: sampleNarrators)
  }
}

#Preview("NarratorsPage - Loading") {
  NarratorsPage(model: .init(isLoading: true))
}

#Preview("NarratorsPage - Empty") {
  NarratorsPage(model: .init())
}

#Preview("NarratorsPage - With Narrators") {
  NarratorsPage(model: .mock)
}
