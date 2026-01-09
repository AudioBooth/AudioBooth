import SwiftUI

struct PeopleRootPage: View {
  enum PersonType: Hashable {
    case authors
    case narrators
  }

  @State private var selectedType: PersonType = .authors

  var body: some View {
    NavigationStack {
      VStack {
        switch selectedType {
        case .authors:
          AuthorsPage(model: AuthorsPageModel())
        case .narrators:
          NarratorsPage(model: NarratorsPageModel())
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Picker("Person Type", selection: $selectedType) {
            Text("Authors").tag(PersonType.authors)
            Text("Narrators").tag(PersonType.narrators)
          }
          .pickerStyle(.segmented)
          .controlSize(.large)
          .font(.subheadline)
          .tint(.primary)
        }
      }
      .navigationDestination(for: NavigationDestination.self) { destination in
        switch destination {
        case .book(let id):
          BookDetailsView(model: BookDetailsViewModel(bookID: id))
        case .series, .author, .narrator, .genre, .tag, .offline:
          LibraryPage(model: LibraryPageModel(destination: destination))
        case .playlist, .collection, .stats:
          EmptyView()
        }
      }
    }
  }
}

#Preview {
  PeopleRootPage()
}
