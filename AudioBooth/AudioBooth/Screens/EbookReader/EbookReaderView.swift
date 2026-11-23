import Combine
import ReadiumNavigator
import SwiftUI
import UIKit

struct EbookReaderView: View {
  static let miniPlayerHeight: CGFloat = 48
  static let miniPlayerSpacing: CGFloat = 8
  static let miniPlayerMaxBottomOffset: CGFloat = 28

  static func miniPlayerInset(safeAreaBottom: CGFloat) -> CGFloat {
    let bottomOffset = safeAreaBottom > 0 ? min(safeAreaBottom, miniPlayerMaxBottomOffset) : miniPlayerSpacing
    return bottomOffset + miniPlayerHeight + miniPlayerSpacing
  }

  @ObservedObject var model: Model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.scenePhase) private var scenePhase

  @State private var showControls = false
  @State private var showSettings = false
  @State private var showZoneEditor = false
  @State private var headerCornerInsets = EdgeInsets()
  @State private var headerTop: CGFloat = 0
  @State private var readerWidth: CGFloat = 0
  @State private var scrubBarFrame: CGRect = .zero

  @State var preferredColorScheme: ColorScheme?

  @ObservedObject private var playerManager = PlayerManager.shared
  private let userPreferences = UserPreferences.shared

  var body: some View {
    contentWithSheets
      .onChange(of: showZoneEditor) { _, isShowing in
        if isShowing { showControls = false }
      }
      .onChange(of: showControls) { _, value in
        model.onShowControlsChanged(value)
      }
      .onChange(of: model.preferences.preferredColorScheme, initial: true) { _, scheme in
        preferredColorScheme = scheme
      }
      .onChange(of: colorScheme) { _, _ in
        if scenePhase == .active && model.preferences.theme == .auto {
          model.onPreferencesChanged(model.preferences)
        }
        preferredColorScheme = model.preferences.preferredColorScheme
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active && model.preferences.theme == .auto {
          model.onPreferencesChanged(model.preferences)
        }
      }
      .onAppear {
        UIApplication.shared.isIdleTimerDisabled = userPreferences.keepScreenAwakeInPlayer
        model.onAppear()
      }
      .onDisappear {
        UIApplication.shared.isIdleTimerDisabled = false
        model.onDisappear()
      }
      .overlay { scrubBubble }
      .statusBarHidden(true)
      .preferredColorScheme(preferredColorScheme)
      .background {
        if volumeButtonsEnabled {
          VolumeButtonObserver(
            onVolumeUp: { model.onTapRight() },
            onVolumeDown: { model.onTapLeft() }
          )
          .allowsHitTesting(false)
        }
      }
  }

  private var content: some View {
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
    .toolbar { toolbarContent }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    if model.cover?.isVisible != true {
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
          EbookReaderControlBar(model: model) { showSettings = true }
            .tint(.primary)
        } else {
          toolbarMiniPlayer
        }
      }
    }
  }

  private var contentWithOverlays: some View {
    content
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.width
      } action: { width in
        readerWidth = width
      }
      .overlay(alignment: .top) {
        if let readAlong = model.readAlong, let message = readAlongStatusMessage(readAlong.status) {
          ReadAlongStatusPill(message: message, status: readAlong.status)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if let message = model.catchUpMessage {
          PositionSyncBanner(
            message: message,
            onCatchUp: model.onCatchUpTapped,
            onDismiss: model.onCatchUpDismissed
          )
          .padding(.top, 8)
          .transition(.move(edge: .top).combined(with: .opacity))
        } else if let chapterProgress = model.chapterProgress, model.preferences.showProgressHeader,
          !showControls, !model.isLoading
        {
          ChapterProgressView(model: chapterProgress)
            .onGeometryChange(for: CGFloat.self) { proxy in
              proxy.frame(in: .global).minY
            } action: { top in
              headerTop = top
            }
            .padding(.leading, headerCornerInsets.leading)
            .padding(.trailing, headerCornerInsets.trailing)
            .foregroundStyle(model.textColor ?? .primary)
            .background(model.backgroundColor.ignoresSafeArea(edges: .top))
            .ignoresHorizontalSafeAreaWhenReservedRegionsAvailable()
            .allowsHitTesting(false)
            .transition(.opacity)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: showControls)
      .animation(.easeInOut(duration: 0.25), value: model.catchUpMessage)
      .animation(.easeInOut(duration: 0.25), value: model.readAlong?.status)
      .overlay {
        if showZoneEditor {
          EbookTapZonesEditorView(preferences: model.preferences) {
            showZoneEditor = false
          }
          .transition(.opacity)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: showZoneEditor)
      .overlay {
        if let cover = model.cover {
          EbookCoverView(model: cover)
        }
      }
  }

  private var contentWithSheets: some View {
    contentWithOverlays
      .sheet(isPresented: $showSettings) {
        EbookReaderPreferencesView(preferences: model.preferences, hasHinge: model.cover?.hasHinge == true) {
          showSettings = false
          Task {
            try? await Task.sleep(for: .milliseconds(400))
            showZoneEditor = true
          }
        }
      }
      .sheet(isPresented: isChaptersPresented) {
        if let chapters = model.chapters {
          EbookChapterPickerSheet(model: chapters)
        }
      }
      .sheet(item: $model.search) { searchModel in
        EbookSearchView(model: searchModel)
      }
      .sheet(item: $model.positionSync) { positionSync in
        PositionSyncSheet(model: positionSync)
      }
      .sheet(isPresented: $model.isPlayerPresented) {
        if let player = playerManager.current {
          fullPlayer(player)
        }
      }
  }

  @ViewBuilder
  private func fullPlayer(_ player: BookPlayer.Model) -> some View {
    if userPreferences.assistedPlayer {
      AssistedPlayer(model: player)
        .displayScaled()
        .interactiveDismissDisabled()
    } else {
      BookPlayer(model: player)
        .displayScaled()
        .interactiveDismissDisabled(player.isLocked)
    }
  }

  @ViewBuilder
  private var toolbarMiniPlayer: some View {
    if #available(iOS 26.0, *) {
      if model.preferences.showMiniPlayer, !showZoneEditor, !model.isLoading, model.error == nil,
        let player = playerManager.current
      {
        EbookMiniPlayer(player: player, scrubBarFrame: $scrubBarFrame, onTap: model.onMiniPlayerTapped)
          .frame(width: max(readerWidth - 32, 0))
          .id(player.id)
      }
    }
  }

  @ViewBuilder
  private var scrubBubble: some View {
    if !model.isPlayerPresented, let progress = playerManager.current?.playbackProgress, progress.isDragging {
      GeometryReader { geometry in
        let origin = geometry.frame(in: .global).origin
        PlaybackProgressView.TimeBubble(time: progress.current, progress: progress.progress)
          .frame(width: scrubBarFrame.width, height: scrubBarFrame.height)
          .position(x: scrubBarFrame.midX - origin.x, y: scrubBarFrame.midY - origin.y - 12)
      }
      .ignoresSafeArea()
    }
  }

  private var isChaptersPresented: Binding<Bool> {
    Binding(
      get: { model.chapters?.isPresented ?? false },
      set: { if let chapters = model.chapters { chapters.isPresented = $0 } }
    )
  }

  private var volumeButtonsEnabled: Bool {
    model.preferences.useVolumeButtonsForPageTurn
      && !model.isLoading
      && model.error == nil
      && !playerManager.isPlaying
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
    ReaderViewControllerWrapper(
      viewController: viewController,
      onTap: { handleTap(at: $0) },
      onPencilDoubleTap: { model.onTapRight() },
      onPencilSqueeze: { model.onTapLeft() }
    )
    .padding(.horizontal, closedHingePadding)
    .background(model.backgroundColor)
    .background {
      GeometryReader { proxy in
        SwiftUI.Color.clear
          .onChange(of: proxy.topCornerInsets(at: headerTop), initial: true) { _, corners in
            headerCornerInsets = corners
          }
          .onChange(of: proxy.size) {
            model.onReaderSizeChanged()
          }
      }
    }
    .ignoresSafeArea()
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

  private var closedHingePadding: CGFloat {
    guard model.cover?.isHingeClosed == true else { return 0 }
    return 15 * model.preferences.pageMargins.value
  }

  private func handleTap(at point: CGPoint) {
    guard model.preferences.tapToNavigate else {
      withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
      return
    }

    let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    let bounds = windowScene?.windows.first?.bounds ?? UIScreen.main.bounds
    let normalizedPoint = CGPoint(x: point.x / bounds.width, y: point.y / bounds.height)

    for zone in model.preferences.tapZones.reversed() where zone.normalizedRect.contains(normalizedPoint) {
      executeAction(zone.action)
      return
    }

    withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
  }

  private func executeAction(_ action: EbookTapAction) {
    switch action {
    case .previousPage:
      model.onTapLeft()
    case .nextPage:
      model.onTapRight()
    case .playPause:
      guard playerManager.current != nil else {
        withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        return
      }
      if playerManager.isPlaying { playerManager.pause() } else { playerManager.play() }
    case .jumpForward:
      guard let player = playerManager.current else {
        withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        return
      }
      player.onSkipForwardTapped(seconds: userPreferences.skipForwardInterval)
    case .jumpBackward:
      guard let player = playerManager.current else {
        withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
        return
      }
      player.onSkipBackwardTapped(seconds: userPreferences.skipBackwardInterval)
    case .autoScrollPlayPause:
      model.onAutoScrollPlayPauseTapped()
    }
  }

  private func readAlongStatusMessage(_ status: ReadAlongCoordinator.Status) -> String? {
    switch status {
    case let .preparing(fraction):
      model.isCatchingUpToNarration
        ? String(localized: "Getting ready… \(fraction.formatted(.percent.precision(.fractionLength(0))))")
        : String(localized: "Preparing Read Along… \(fraction.formatted(.percent.precision(.fractionLength(0))))")
    case .locating:
      model.isCatchingUpToNarration
        ? String(localized: "Finding where the narrator is…")
        : String(localized: "Listening for your place in the book…")
    case let .failed(message):
      message
    case .off, .following:
      nil
    }
  }
}

extension View {
  @ViewBuilder
  fileprivate func ignoresHorizontalSafeAreaWhenReservedRegionsAvailable() -> some View {
    if #available(iOS 27.1, *) {
      ignoresSafeArea(edges: .horizontal)
    } else {
      self
    }
  }
}

struct ReaderViewControllerWrapper: UIViewControllerRepresentable {
  let viewController: UIViewController
  var onTap: ((CGPoint) -> Void)?
  var onPencilDoubleTap: (() -> Void)?
  var onPencilSqueeze: (() -> Void)?

  func makeUIViewController(context: Context) -> UIViewController {
    let coordinator = context.coordinator
    (viewController as? VisualNavigator)?.addObserver(
      .activate { [weak viewController] event in
        guard let view = viewController?.view else { return false }
        coordinator.onTap?(view.convert(event.location, to: nil))
        return false
      }
    )

    if #available(iOS 17.5, *) {
      let interaction = UIPencilInteraction()
      interaction.delegate = context.coordinator
      viewController.view.addInteraction(interaction)
    }
    return viewController
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    context.coordinator.onTap = onTap
    context.coordinator.onDoubleTap = onPencilDoubleTap
    context.coordinator.onSqueeze = onPencilSqueeze
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onTap: onTap, onDoubleTap: onPencilDoubleTap, onSqueeze: onPencilSqueeze)
  }

  final class Coordinator: NSObject, UIPencilInteractionDelegate {
    var onTap: ((CGPoint) -> Void)?
    var onDoubleTap: (() -> Void)?
    var onSqueeze: (() -> Void)?

    init(onTap: ((CGPoint) -> Void)?, onDoubleTap: (() -> Void)?, onSqueeze: (() -> Void)?) {
      self.onTap = onTap
      self.onDoubleTap = onDoubleTap
      self.onSqueeze = onSqueeze
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
      guard UIPencilInteraction.preferredTapAction != .ignore else { return }
      onDoubleTap?()
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
      guard squeeze.phase == .ended else { return }
      guard UIPencilInteraction.preferredSqueezeAction != .ignore else { return }
      onSqueeze?()
    }
  }
}

extension EbookReaderView {
  @Observable
  class Model: ObservableObject, Identifiable {
    let id = UUID()

    var isLoading: Bool
    var error: String?
    var readerViewController: UIViewController?
    var progress: Double
    var page: (current: Int, total: Int)?
    var chapters: EbookChapterPickerSheet.Model?
    var chapterProgress: ChapterProgressView.Model?
    var preferences: EbookReaderPreferences
    var backgroundColor: SwiftUI.Color
    var textColor: SwiftUI.Color?
    var cover: EbookCoverView.Model?
    var supportsSettings: Bool
    var search: EbookSearchView.Model?
    var supportsSearch: Bool

    var supportsReadAlong: Bool
    var readAlong: ReadAlongCoordinator?
    var catchUpMessage: LocalizedStringResource?
    var isCatchingUpToNarration: Bool = false
    var positionSync: PositionSyncSheet.Model?
    var isPlayerPresented: Bool = false
    var isFollowingMediaOverlay: Bool = false
    var hasAudiobook: Bool = false

    func onAppear() {}
    func onDisappear() {}
    func onTableOfContentsTapped() {}
    func onSettingsTapped() {}
    func onProgressTapped() {}
    func onSearchTapped() {}
    func onPreferencesChanged(_ preferences: EbookReaderPreferences) {}
    func onTapLeft() {}
    func onTapRight() {}
    func onAutoScrollPlayPauseTapped() {}
    func onShowControlsChanged(_ isVisible: Bool) {}
    func onReaderSizeChanged() {}
    func onReadAlongTapped() {}
    func onCatchUpTapped() {}
    func onCatchUpDismissed(_ scope: PositionSyncOffer.Dismissal) {}
    func onNowPlayingTapped() {}
    func onMiniPlayerTapped() {}

    init(
      isLoading: Bool = true,
      error: String? = nil,
      readerViewController: UIViewController? = nil,
      progress: Double = 0.0,
      page: (current: Int, total: Int)? = nil,
      chapters: EbookChapterPickerSheet.Model? = nil,
      preferences: EbookReaderPreferences = EbookReaderPreferences(),
      backgroundColor: SwiftUI.Color = .clear,
      supportsSettings: Bool = false,
      search: EbookSearchView.Model? = nil,
      supportsSearch: Bool = false,
      supportsReadAlong: Bool = false
    ) {
      self.isLoading = isLoading
      self.error = error
      self.readerViewController = readerViewController
      self.progress = progress
      self.page = page
      self.chapters = chapters
      self.preferences = preferences
      self.backgroundColor = backgroundColor
      self.supportsSettings = supportsSettings
      self.search = search
      self.supportsSearch = supportsSearch
      self.supportsReadAlong = supportsReadAlong
    }
  }
}
