import Combine
import SwiftUI

struct EbookPlayerSheet: View {
  @ObservedObject var model: Model

  var body: some View {
    VStack(spacing: 24) {
      if let message = model.player.positionSyncMessage {
        PositionSyncBanner(
          message: message,
          onCatchUp: model.onCatchUpTapped,
          onDismiss: model.player.onPositionSyncDismissed
        )
        .transition(.move(edge: .top).combined(with: .opacity))
      }

      VStack(spacing: 32) {
        if let chapter = model.player.chapters?.current {
          Text(chapter.title)
            .font(.headline)
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
        }

        BookPlayerPlaybackSection(model: model.player)
      }
      .padding(.horizontal, 24)
    }
    .padding(.top, 50)
    .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 50 : 0)
    .animation(.easeInOut, value: model.player.positionSyncMessage)
    .preferredColorScheme(.dark)
    .presentationDragIndicator(.visible)
    .onAppear(perform: model.player.onAppear)
  }
}

extension EbookPlayerSheet {
  @Observable
  class Model: ObservableObject {
    let player: BookPlayer.Model
    var isPresented: Bool

    func onCatchUpTapped() {}

    init(
      player: BookPlayer.Model,
      isPresented: Bool = false
    ) {
      self.player = player
      self.isPresented = isPresented
    }
  }
}
