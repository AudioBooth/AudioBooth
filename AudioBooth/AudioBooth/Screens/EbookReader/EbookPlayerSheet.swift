import SwiftUI

struct EbookPlayerSheet: View {
  @ObservedObject var player: BookPlayer.Model

  var body: some View {
    VStack(spacing: 32) {
      if let chapter = player.chapters?.current {
        Text(chapter.title)
          .font(.headline)
          .foregroundColor(.white)
          .lineLimit(1)
          .padding(.horizontal, 8)
      }

      BookPlayerPlaybackSection(model: player)
    }
    .padding(.top, 50)
    .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 50 : 0)
    .padding(.horizontal, 24)
    .preferredColorScheme(.dark)
    .presentationDragIndicator(.visible)
  }
}
