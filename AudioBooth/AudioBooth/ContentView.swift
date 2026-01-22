import API
import Models
import SwiftData
import SwiftUI

struct ContentView: View {
  @StateObject private var playerManager = PlayerManager.shared
  @ObservedObject private var libraries = Audiobookshelf.shared.libraries

  @Environment(\.colorScheme) private var colorScheme

  @State private var isKeyboardVisible = false
  @State private var selectedTab: TabSelection = .home
  @State private var selectedCollectionType: CollectionsRootPage.CollectionType = .series
  @State private var selectedLibraryType: LibraryRootPage.LibraryType = .library

  enum TabSelection {
    case home, library, collections, downloads, search
  }

  private var hasSelectedLibrary: Bool {
    libraries.current != nil
  }

  private var tabSelection: Binding<TabSelection> {
    Binding(
      get: { selectedTab },
      set: { newValue in
        if newValue == selectedTab {
          switch newValue {
          case .library:
            selectedLibraryType = selectedLibraryType.next
          case .collections:
            selectedCollectionType = selectedCollectionType.next
          default:
            break
          }
        }
        selectedTab = newValue
      }
    )
  }

  var body: some View {
    content
      .adaptivePresentation(isPresented: $playerManager.isShowingFullPlayer) {
        if let currentPlayer = playerManager.current {
          BookPlayer(model: currentPlayer)
            .presentationDetents([.large])
            .presentationDragIndicator(UIAccessibility.isVoiceOverRunning ? .hidden : .visible)
        }
      }
      .fullScreenCover(item: $playerManager.reader) { reader in
        NavigationStack {
          EbookReaderView(model: reader)
        }
      }
      .sheet(isPresented: $playerManager.isShowingQueue) {
        PlayerQueueView(
          model: PlayerQueueViewModel {
            playerManager.isShowingQueue = false
          }
        )
        .presentationDetents([.large])
      }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
        isKeyboardVisible = true
      }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
        isKeyboardVisible = false
      }
      .handleDeepLinks()
  }

  @ViewBuilder
  var content: some View {
    if #available(iOS 26.0, *) {
      modernTabView
    } else {
      legacyTabView
    }
  }

  @available(iOS 26.0, *)
  @ViewBuilder
  private var modernTabView: some View {
    TabView(selection: tabSelection) {
      Tab("Home", systemImage: "house", value: .home) {
        HomePage(model: HomePageModel())
      }

      if hasSelectedLibrary {
        Tab("Library", systemImage: "books.vertical.fill", value: .library) {
          LibraryRootPage(selectedType: $selectedLibraryType)
        }

        Tab("Collections", systemImage: "square.stack.3d.up.fill", value: .collections) {
          CollectionsRootPage(selectedType: $selectedCollectionType)
        }

        Tab("Downloads", systemImage: "arrow.down.circle.fill", value: .downloads) {
          DownloadsRootPage()
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
        .padding(.bottom, 0.5)
        .safeAreaInset(edge: .bottom) { miniPlayer }
        .tabItem {
          Image(systemName: "house")
          Text("Home")
        }

      if hasSelectedLibrary {
        LibraryRootPage(selectedType: $selectedLibraryType)
          .padding(.bottom, 0.5)
          .safeAreaInset(edge: .bottom) { miniPlayer }
          .tabItem {
            Image(systemName: "books.vertical.fill")
            Text("Library")
          }

        CollectionsRootPage(selectedType: $selectedCollectionType)
          .padding(.bottom, 0.5)
          .safeAreaInset(edge: .bottom) { miniPlayer }
          .tabItem {
            Image(systemName: "square.stack.3d.up.fill")
            Text("Collections")
          }

        DownloadsRootPage()
          .padding(.bottom, 0.5)
          .safeAreaInset(edge: .bottom) { miniPlayer }
          .tabItem {
            Image(systemName: "arrow.down.circle.fill")
            Text("Downloads")
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
