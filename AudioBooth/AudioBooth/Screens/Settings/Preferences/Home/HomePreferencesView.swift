import SwiftUI

struct HomePreferencesView: View {
  @ObservedObject var preferences = UserPreferences.shared

  @State private var allSections: [HomeSection] = []
  @State private var enabledSections: Set<HomeSection> = []

  var body: some View {
    Form {
      Section {
        List {
          ForEach(allSections) { section in
            HStack {
              Text(section.displayName)
                .bold()

              Spacer()

              if section.canBeDisabled {
                Toggle("", isOn: binding(for: section))
              }
            }
            //            .moveDisabled(!enabledSections.contains(section))
          }
          .onMove(perform: move)
        }
      } footer: {
        Text(
          "Drag to reorder enabled sections. Continue Listening and Available Offline cannot be disabled."
        )
        .font(.caption)
      }
    }
    .navigationTitle("Home")
    .environment(\.editMode, .constant(.active))
    .onAppear {
      loadSections()
    }
    .onDisappear {
      saveSections()
    }
  }

  private func loadSections() {
    let storedSections = preferences.homeSections

    if storedSections.isEmpty {
      allSections = Array(HomeSection.allCases)
      enabledSections = Set(HomeSection.allCases)
      return
    }

    let storedSet = Set(storedSections)
    let disabledSections = HomeSection.allCases.filter {
      !storedSet.contains($0) && $0.canBeDisabled
    }

    allSections = storedSections + disabledSections
    enabledSections = storedSet
  }

  private func saveSections() {
    preferences.homeSections = allSections.filter { enabledSections.contains($0) }
  }

  private func move(from source: IndexSet, to destination: Int) {
    allSections.move(fromOffsets: source, toOffset: destination)
  }

  private func binding(for section: HomeSection) -> Binding<Bool> {
    Binding(
      get: {
        enabledSections.contains(section)
      },
      set: { isEnabled in
        if isEnabled {
          enabledSections.insert(section)
        } else {
          enabledSections.remove(section)
        }
      }
    )
  }
}

#Preview {
  NavigationStack {
    HomePreferencesView()
  }
}
