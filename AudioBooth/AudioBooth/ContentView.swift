import API
import SwiftData
import SwiftUI

struct ContentView: View {
  @StateObject private var playerManager = PlayerManager.shared
  @ObservedObject private var libraries = Audiobookshelf.shared.libraries

  @Environment(\.colorScheme) private var colorScheme

  @State private var isKeyboardVisible = false
  @State private var selectedTab: TabSelection = .home

  enum TabSelection {
    case home, library, collections, authors, search
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

        Tab("Collections", systemImage: "square.stack.3d.up.fill", value: .collections) {
          CollectionsRootPage()
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
      Group {
        if let currentPlayer = playerManager.current {
          MiniBookPlayer(player: currentPlayer)
            .equatable()
        } else {
          HStack(spacing: 12) {
            Image(systemName: "book.circle")
              .font(.title2)

            Text("Select a book to begin")
              .font(.subheadline)
          }
          .frame(maxWidth: .infinity)
          .padding()
        }
      }
      .colorScheme(colorScheme)
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

        CollectionsRootPage()
          .safeAreaInset(edge: .bottom) { miniPlayer }
          .tabItem {
            Image(systemName: "square.stack.3d.up.fill")
            Text("Collections")
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
