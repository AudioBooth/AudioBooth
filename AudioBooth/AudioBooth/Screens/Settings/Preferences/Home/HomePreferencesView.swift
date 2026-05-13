import SwiftUI

struct HomePreferencesView: View {
  @Environment(\.appTheme) var theme
  @ObservedObject var preferences = UserPreferences.shared

  @State private var allSections: [HomeSection] = []
  @State private var enabledSections: Set<HomeSection> = []

  var body: some View {
    Form {
      Section {
        CoverSizePickerView(selection: $preferences.continueSectionSize)
          .listRowBackground(theme.colors.background.card)
      } header: {
        Text("Cover Size")
      } footer: {
        Text("Cover art size for Continue Listening and Continue Reading.")
          .font(.caption)
      }

      Section {
        List {
          ForEach(allSections) { section in
            sectionRow(section)
              .listRowBackground(theme.colors.background.card)
          }
          .onMove(perform: move)
        }
      } header: {
        HStack {
          Text("Sections")
          Spacer()
          Button("Reset Order", action: resetOrder)
            .font(.caption)
            .fontWeight(.semibold)
            .textCase(nil)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.colors.background.page)
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

  private func resetOrder() {
    let defaults = HomeSection.defaultCases
    let defaultSet = Set(defaults)
    let remaining = HomeSection.allCases.filter {
      !defaultSet.contains($0) && $0.canBeDisabled
    }
    allSections = defaults + remaining
    enabledSections = defaultSet
  }

  @ViewBuilder
  private func sectionRow(_ section: HomeSection) -> some View {
    HStack(spacing: 12) {
      PreferenceRow(
        systemImage: section.systemImage,
        tint: section.tint,
        title: section.displayName,
        subtitle: section.canBeDisabled ? nil : String(localized: "Always visible")
      )

      Spacer()

      if section.canBeDisabled {
        Toggle(isOn: binding(for: section)) {}
          .labelsHidden()
      }
    }
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

extension HomeSection {
  var systemImage: String {
    switch self {
    case .listeningStats: "chart.bar"
    case .pinnedPlaylist: "pin.fill"
    case .continueListening: "play.circle"
    case .continueReading: "book"
    case .continueSeries: "rectangle.stack"
    case .recentlyAdded: "clock"
    case .recentSeries: "rectangle.stack.badge.plus"
    case .discover: "sparkles"
    case .listenAgain: "arrow.clockwise"
    case .newestAuthors: "person.circle"
    case .newestEpisodes: "dot.radiowaves.left.and.right"
    case .readAgain: "book.closed"
    }
  }

  var tint: Color {
    switch self {
    case .listeningStats: .orange
    case .pinnedPlaylist: .yellow
    case .continueListening: .orange
    case .continueReading: .brown
    case .continueSeries: .purple
    case .recentlyAdded: .blue
    case .recentSeries: .blue
    case .discover: .pink
    case .listenAgain: .green
    case .newestAuthors: .mint
    case .newestEpisodes: .blue
    case .readAgain: .brown
    }
  }
}

#Preview {
  NavigationStack {
    HomePreferencesView()
  }
}
