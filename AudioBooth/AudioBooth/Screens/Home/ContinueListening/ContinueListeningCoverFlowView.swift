import Combine
import SwiftUI

struct ContinueListeningCoverFlowView: View {
  @ObservedObject var model: Model
  @ObservedObject private var preferences = UserPreferences.shared

  @ScaledMetric(relativeTo: .title) private var baseCoverSize: CGFloat = 150

  private let coordinateSpaceName = "coverFlowScroll"

  private var coverSize: CGFloat {
    preferences.continueSectionSize.value / 120 * baseCoverSize
  }

  var body: some View {
    VStack(spacing: 4) {
      coverFlow

      overlayInfo
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .animation(.smooth(duration: 0.25), value: model.focusedID)
    }
  }

  private var coverFlow: some View {
    GeometryReader { container in
      let containerWidth = container.size.width
      let sidePadding = max(0, (containerWidth - coverSize) / 2)

      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: coverSize * 0.15) {
            ForEach(model.items, id: \.id) { item in
              card(for: item, containerWidth: containerWidth)
                .frame(width: coverSize, height: coverSize)
                .id(item.id)
            }
          }
          .padding(.bottom, coverSize * 0.06)
          .scrollTargetLayout()
        }
        .contentMargins(.horizontal, sidePadding, for: .scrollContent)
        .scrollClipDisabled()
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $model.focusedID, anchor: .center)
        .coordinateSpace(name: coordinateSpaceName)
        .onChange(of: containerWidth) { _, newWidth in
          guard newWidth > 0, let id = model.focusedID else { return }
          DispatchQueue.main.async {
            proxy.scrollTo(id, anchor: .center)
          }
        }
      }
    }
    .frame(height: coverSize * 1.08)
  }

  private func card(for item: BookCard.Model, containerWidth: CGFloat) -> some View {
    NavigationLink(value: navigationDestination(for: item)) {
      ZStack {
        Color.clear

        Cover(model: item.cover)
          .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 6)
          .visualEffect { content, geometry in
            let cardMidX = geometry.frame(in: .named(coordinateSpaceName)).midX
            let half = max(containerWidth / 2, 1)
            let normalized = max(-1.0, min(1.0, Double((cardMidX - containerWidth / 2) / half)))
            return
              content
              .rotation3DEffect(
                .degrees(normalized * -55),
                axis: (x: 0, y: 1, z: 0),
                anchor: normalized > 0 ? .leading : .trailing,
                perspective: 0.5
              )
              .scaleEffect(1 - abs(normalized) * 0.18)
              .opacity(1 - abs(normalized) * 0.35)
          }
          .allowsHitTesting(false)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay {
      if model.focusedID != item.id {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture {
            withAnimation(.smooth(duration: 0.4)) {
              model.focusedID = item.id
            }
          }
      }
    }
    .contextMenu {
      if model.focusedID == item.id {
        if let menu = item.contextMenu {
          BookCardContextMenu(model: menu)
        } else if let menu = item.episodeContextMenu {
          PodcastEpisodeContextMenu(model: menu)
        }
      }
    }
    .menuOrder(.priority)
    .accessibilityLabel(accessibilityLabel(for: item))
    .bookCardAccessibilityActions(model: item)
    .onAppear(perform: item.onAppear)
  }

  private func accessibilityLabel(for item: BookCard.Model) -> String {
    if let author = item.author, !author.isEmpty {
      "\(item.title), \(author)"
    } else {
      item.title
    }
  }

  private func navigationDestination(for item: BookCard.Model) -> NavigationDestination {
    if let id = item.podcastID {
      .podcast(id: id, episodeID: item.id)
    } else {
      .book(id: item.id)
    }
  }

  @ViewBuilder
  private var overlayInfo: some View {
    if let focused = model.focusedItem {
      VStack(spacing: 2) {
        if !preferences.cardMinimalMode {
          Text(focused.title)
            .font(.headline)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .id("title-\(focused.id)")
            .transition(.opacity)

          if let subtitle = focused.author, !subtitle.isEmpty {
            Text(subtitle)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .lineLimit(1)
              .id("subtitle-\(focused.id)")
              .transition(.opacity)
          }
        }

        if preferences.showContinueTimeRemaining, let remaining = focused.timeRemaining {
          Text(remaining.formattedTimeRemaining)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(remaining.accessibilityTimeRemaining)
            .id("time-\(focused.id)")
            .transition(.opacity)
        }
      }
    } else {
      Color.clear.frame(height: 1)
    }
  }
}

extension ContinueListeningCoverFlowView {
  @Observable
  class Model: ObservableObject {
    var items: [BookCard.Model]
    var focusedID: String?

    var focusedItem: BookCard.Model? {
      guard let focusedID else { return items.first }
      return items.first { $0.id == focusedID } ?? items.first
    }

    init(items: [BookCard.Model] = [], focusedID: String? = nil) {
      self.items = items
      if let focusedID, items.contains(where: { $0.id == focusedID }) {
        self.focusedID = focusedID
      } else if let playingID = PlayerManager.shared.current?.id,
        items.contains(where: { $0.id == playingID })
      {
        self.focusedID = playingID
      } else {
        self.focusedID = items.first?.id
      }
    }
  }
}

#Preview {
  NavigationStack {
    ContinueListeningCoverFlowView(
      model: .init(items: [
        BookCard.Model(
          title: "The Lord of the Rings",
          cover: Cover.Model(
            url: URL(string: "https://m.media-amazon.com/images/I/51YHc7SK5HL._SL500_.jpg"),
            progress: 0.45
          ),
          author: "J.R.R. Tolkien",
          timeRemaining: 30720
        ),
        BookCard.Model(
          title: "Dune",
          cover: Cover.Model(
            url: URL(string: "https://m.media-amazon.com/images/I/41rrXYM-wHL._SL500_.jpg"),
            progress: 0.12
          ),
          author: "Frank Herbert",
          timeRemaining: 8100
        ),
        BookCard.Model(
          title: "Foundation",
          cover: Cover.Model(
            url: URL(string: "https://m.media-amazon.com/images/I/51I5xPlDi9L._SL500_.jpg"),
            progress: 0.78
          ),
          author: "Isaac Asimov",
          timeRemaining: 3780
        ),
      ])
    )
    .padding(.vertical)
  }
}
