import API
import SwiftData
import SwiftUI

struct ContentView: View {
  @StateObject private var playerManager = PlayerManager.shared
  @ObservedObject private var libraries = Audiobookshelf.shared.libraries
  @Environment(\.scenePhase) private var scenePhase

  @State private var isKeyboardVisible = false
  @State private var selectedTab: TabSelection = .home

  enum TabSelection {
    case home, library, series, authors, search
  }

  private var hasSelectedLibrary: Bool {
    libraries.current != nil
  }

  var body: some View {
    Group {
      if #available(iOS 26.0, *) {
        modernTabView
      } else {
        legacyTabView
      }
    }
    .sheet(isPresented: $playerManager.isShowingFullPlayer) {
      if let currentPlayer = playerManager.current {
        BookPlayer(model: .constant(currentPlayer))
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification))
    { _ in
      isKeyboardVisible = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
    { _ in
      isKeyboardVisible = false
    }
    .onChange(of: scenePhase) { _, newPhase in
      AppStateManager.shared.updateScenePhase(newPhase)
    }

  }

  @available(iOS 26.0, *)
  @ViewBuilder
  private var modernTabView: some View {
    TabView(selection: $selectedTab) {
      Tab("Home", systemImage: "house", value: .home) {
        HomePage(model: HomePageModel())
      }

      if hasSelectedLibrary {
        Tab("Library", systemImage: "books.vertical.fill", value: .library) {
          LibraryRootPage()
        }

        Tab("Series", systemImage: "square.stack.3d.up.fill", value: .series) {
          SeriesPage(model: SeriesPageModel())
        }

        Tab("Authors", systemImage: "person.crop.rectangle.stack", value: .authors) {
          AuthorsPage(model: AuthorsPageModel())
        }

        Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
          SearchPage(model: SearchViewModel())
        }
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory {
      if let currentPlayer = playerManager.current, !isKeyboardVisible {
        MiniBookPlayer(player: currentPlayer)
          .equatable()
          .glassEffect()
      }
    }
  }

  @ViewBuilder
  private var legacyTabView: some View {
    TabView {
      HomePage(model: HomePageModel())
        .safeAreaInset(edge: .bottom) { miniPlayer }
        .tabItem {
          Image(systemName: "house")
          Text("Home")
        }

      if hasSelectedLibrary {
        LibraryRootPage()
          .safeAreaInset(edge: .bottom) { miniPlayer }
          .tabItem {
            Image(systemName: "books.vertical.fill")
            Text("Library")
          }

        SeriesPage(model: SeriesPageModel())
          .safeAreaInset(edge: .bottom) { miniPlayer }
          .tabItem {
            Image(systemName: "square.stack.3d.up.fill")
            Text("Series")
          }

        AuthorsPage(model: AuthorsPageModel())
          .safeAreaInset(edge: .bottom) { miniPlayer }
          .tabItem {
            Image(systemName: "person.crop.rectangle.stack")
            Text("Authors")
          }
      }
    }
  }

  @ViewBuilder
  private var miniPlayer: some View {
    if let currentPlayer = playerManager.current, !isKeyboardVisible {
      LegacyMiniBookPlayer(player: currentPlayer)
        .id(currentPlayer.id)
        .transition(.move(edge: .bottom))
        .animation(.easeInOut(duration: 0.3), value: playerManager.hasActivePlayer)
    }
  }
}

#Preview {
  ContentView()
}
