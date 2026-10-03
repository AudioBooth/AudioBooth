import Combine
import SwiftUI

struct BookCardCollectionSelector: ViewModifier {
  @ObservedObject var model: BookCard.Model

  func body(content: Content) -> some View {
    let selector = model.contextMenu?.collectionSelector ?? model.episodeContextMenu?.collectionSelector
    let isConfirmingRemoval = model.contextMenu?.isConfirmingRemoveFromContinueListening ?? false

    content
      .sheet(
        item: Binding(
          get: { selector },
          set: { newValue in
            if model.contextMenu != nil {
              model.contextMenu?.collectionSelector = newValue
            } else {
              model.episodeContextMenu?.collectionSelector = newValue
            }
          }
        )
      ) { sheetModel in
        CollectionSelectorSheet(model: sheetModel)
      }
      .confirmationDialog(
        "This book is currently playing",
        isPresented: Binding(
          get: { isConfirmingRemoval },
          set: { model.contextMenu?.isConfirmingRemoveFromContinueListening = $0 }
        ),
        titleVisibility: .visible
      ) {
        Button("Remove and Stop", role: .destructive) {
          model.contextMenu?.onRemoveFromContinueListeningConfirmed()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Removing it from Continue Listening will stop playback.")
      }
  }
}

extension View {
  func bookCardCollectionSelector(model: BookCard.Model) -> some View {
    modifier(BookCardCollectionSelector(model: model))
  }
}
