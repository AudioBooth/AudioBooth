import SwiftUI

struct HomePreferencesView: View {
  @ObservedObject var preferences = UserPreferences.shared

  @State private var allSections: [HomeSection] = []
  @State private var enabledSections: Set<HomeSection> = []

  var body: some View {
    Form {
      Section {
        Picker("Continue Section Size", selection: $preferences.continueSectionSize) {
          ForEach(ContinueSectionSize.allCases, id: \.self) { size in
            Text(size.displayText).tag(size)
          }
        }
      } footer: {
        Text("Adjusts the cover size for Continue Listening and Continue Reading sections.")
          .font(.caption)
      }

      Section {
        List {
          ForEach(allSections) { section in
            HStack {
              Text(section.displayName)
                .font(.subheadline)
                .bold()

              Spacer()

              if section.canBeDisabled {
                Toggle(isOn: binding(for: section)) {}
              }
            }
          }
          .onMove(perform: move)
        }
      } footer: {
        Text(
          "Drag to reorder enabled sections. Continue Listening and Continue Reading cannot be disabled."
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
