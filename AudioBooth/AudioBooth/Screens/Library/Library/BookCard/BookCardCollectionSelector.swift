import Combine
import SwiftUI

struct BookCardCollectionSelector: ViewModifier {
  @ObservedObject var model: BookCard.Model

  func body(content: Content) -> some View {
    let selector = model.contextMenu?.collectionSelector ?? model.episodeContextMenu?.collectionSelector

    content.sheet(
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
  }
}

extension View {
  func bookCardCollectionSelector(model: BookCard.Model) -> some View {
    modifier(BookCardCollectionSelector(model: model))
  }
}
