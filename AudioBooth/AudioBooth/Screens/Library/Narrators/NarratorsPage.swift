import Combine
import NukeUI
import SwiftUI

struct NarratorsPage: View {
  @ObservedObject var model: Model

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
      sectionLetter(for: narrator.name)
    }

    return grouped.map { letter, narrators in
      NarratorSection(id: letter, letter: letter, narrators: narrators)
    }.sorted { lhs, rhs in
      if lhs.letter == "#" { return false }
      if rhs.letter == "#" { return true }
      return lhs.letter < rhs.letter
    }
  }

  private func sectionLetter(for name: String) -> String {
    guard let firstChar = name.uppercased().first else { return "#" }
    let validLetters: Set<Character> = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    return validLetters.contains(firstChar) ? String(firstChar) : "#"
  }

  var narratorsRowContent: some View {
    ScrollViewReader { proxy in
      ScrollView {
        narratorsList
      }
      .overlay(alignment: .trailing) {
        AlphabetScrollBar(
          onLetterTapped: { model.onLetterTapped($0) }
        )
      }
      .scrollIndicators(.hidden)
      .onChange(of: model.scrollTarget) { _, target in
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.1)) {
          proxy.scrollTo(target, anchor: .top)
        }
      }
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

      Color.clear
        .frame(height: 1)
        .id(Self.bottomScrollID)
    }
  }

  func narratorRow(for narrator: NarratorCard.Model) -> some View {
    NavigationLink(value: NavigationDestination.narrator(name: narrator.name)) {
      VStack(alignment: .leading, spacing: 2) {
        Text(narrator.name)
          .font(.body)
          .frame(maxWidth: .infinity, alignment: .leading)

        if narrator.bookCount > 0 {
          Text("^[\(narrator.bookCount) book](inflect: true)")
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
  static let bottomScrollID = "BOTTOM"

  struct NarratorSection: Identifiable {
    let id: String
    let letter: String
    let narrators: [NarratorCard.Model]
  }

  @Observable class Model: ObservableObject {
    var isLoading: Bool
    var scrollTarget: String?

    var narrators: [NarratorCard.Model]
    var searchViewModel: SearchView.Model = SearchView.Model()

    func onAppear() {}
    func refresh() async {}
    func onLetterTapped(_ letter: String) {}

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
