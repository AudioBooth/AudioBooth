import Combine
import SwiftUI
import UIKit

struct EbookReaderView: View {
  @ObservedObject var model: Model
  @Environment(\.dismiss) private var dismiss
  @State private var showControls = false
  @State private var showSettings = false

  var body: some View {
    ZStack {
      if model.isLoading {
        loadingView
      } else if let error = model.error {
        errorView(error)
      } else if let viewController = model.readerViewController {
        readerView(viewController)
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        if showControls, !model.isLoading, model.error == nil, model.supportsSearch {
          Button {
            model.onSearchTapped()
          } label: {
            Label("Search", systemImage: "magnifyingglass")
          }
          .transition(.opacity)
          .tint(.primary)
        }
      }

      ToolbarItem(placement: .topBarTrailing) {
        if showControls || model.isLoading {
          Button {
            dismiss()
          } label: {
            Label("Close", systemImage: "xmark")
          }
          .transition(.opacity)
          .tint(.primary)
        }
      }

      ToolbarItem(placement: .bottomBar) {
        if !model.isLoading, model.error == nil, showControls {
          bottomControlBar
            .tint(.primary)
        }
      }
    }
    .sheet(isPresented: $showSettings) {
      EbookReaderPreferencesView(preferences: model.preferences)
    }
    .sheet(
      isPresented: Binding(
        get: { model.chapters?.isPresented ?? false },
        set: { if let chapters = model.chapters { chapters.isPresented = $0 } }
      )
    ) {
      if let chapters = model.chapters {
        EbookChapterPickerSheet(model: chapters)
      }
    }
    .sheet(item: $model.search) { searchModel in
      EbookSearchView(model: searchModel)
    }
    .onAppear(perform: model.onAppear)
    .onDisappear(perform: model.onDisappear)
  }

  private var loadingView: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.5)
        .tint(.primary)
      Text("Loading ebook...")
        .font(.headline)
        .foregroundColor(.primary.opacity(0.9))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func errorView(_ error: String) -> some View {
    ContentUnavailableView {
      Label("Unable to Load Ebook", systemImage: "exclamationmark.triangle")
    } description: {
      Text(error)
    } actions: {
      Button("Close") {
        dismiss()
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func readerView(_ viewController: UIViewController) -> some View {
    ReaderViewControllerWrapper(viewController: viewController)
      .ignoresSafeArea(.all)
      .simultaneousGesture(
        SpatialTapGesture()
          .onEnded { value in
            handleTap(at: value.location.x)
          }
      )
      .animation(.easeInOut(duration: 0.2), value: showControls)
      .onAppear {
        showControls = true
        Task {
          try? await Task.sleep(for: .seconds(2))
          withAnimation {
            showControls = false
          }
        }
      }
  }

  private func handleTap(at x: CGFloat) {
    let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    let windowWidth = windowScene?.windows.first?.bounds.width ?? UIScreen.main.bounds.width
    let leftThreshold = windowWidth * 0.25
    let rightThreshold = windowWidth * 0.75

    if model.preferences.tapToNavigate, x < leftThreshold {
      model.onTapLeft()
    } else if model.preferences.tapToNavigate, x > rightThreshold {
      model.onTapRight()
    } else {
      withAnimation(.easeInOut(duration: 0.2)) {
        showControls.toggle()
      }
    }
  }

  @ViewBuilder
  private var bottomControlBar: some View {
    HStack(alignment: .bottom, spacing: 0) {
      if model.chapters != nil {
        Button(action: { model.onTableOfContentsTapped() }) {
          VStack(spacing: 6) {
            Image(systemName: "list.bullet")
              .font(.system(size: 20))
            Text("Contents")
              .font(.caption2)
          }
        }
        .frame(maxWidth: .infinity)
      }

      if model.supportsSettings {
        Button(action: {
          model.onSettingsTapped()
          showSettings = true
        }) {
          VStack(spacing: 6) {
            Image(systemName: "textformat.size")
              .font(.system(size: 20))
            Text("Settings")
              .font(.caption2)
          }
        }
        .frame(maxWidth: .infinity)
      }

      Button(action: { model.onProgressTapped() }) {
        VStack(spacing: 6) {
          Text(model.progress.formatted(.percent.precision(.fractionLength(0))))
            .font(.system(size: 16, weight: .medium))
          Text("Progress")
            .font(.caption2)
        }
      }
      .frame(maxWidth: .infinity)
    }
    .padding(.vertical, 8)
  }
}

struct ReaderViewControllerWrapper: UIViewControllerRepresentable {
  let viewController: UIViewController

  func makeUIViewController(context: Context) -> UIViewController {
    viewController
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

extension EbookReaderView {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()

    var isLoading: Bool
    var error: String?
    var readerViewController: UIViewController?
    var progress: Double
    var chapters: EbookChapterPickerSheet.Model?
    var preferences: EbookReaderPreferences
    var supportsSettings: Bool
    var search: EbookSearchView.Model?
    var supportsSearch: Bool

    func onAppear() {}
    func onDisappear() {}
    func onTableOfContentsTapped() {}
    func onSettingsTapped() {}
    func onProgressTapped() {}
    func onSearchTapped() {}
    func onPreferencesChanged(_ preferences: EbookReaderPreferences) {}
    func onTapLeft() {}
    func onTapRight() {}

    init(
      isLoading: Bool = true,
      error: String? = nil,
      readerViewController: UIViewController? = nil,
      bookTitle: String = "",
      currentChapter: String? = nil,
      progress: Double = 0.0,
      chapters: EbookChapterPickerSheet.Model? = nil,
      preferences: EbookReaderPreferences = EbookReaderPreferences(),
      supportsSettings: Bool = false,
      search: EbookSearchView.Model? = nil,
      supportsSearch: Bool = false
    ) {
      self.isLoading = isLoading
      self.error = error
      self.readerViewController = readerViewController
      self.progress = progress
      self.chapters = chapters
      self.preferences = preferences
      self.supportsSettings = supportsSettings
      self.search = search
      self.supportsSearch = supportsSearch
    }
  }
}
