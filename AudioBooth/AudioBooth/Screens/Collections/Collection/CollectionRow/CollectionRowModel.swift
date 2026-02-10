import API
import Foundation

final class CollectionRowModel: CollectionRow.Model {
  init(collection: any CollectionLike) {
    super.init(
      id: collection.id,
      name: collection.name,
      description: collection.description,
      count: collection.itemCount,
      covers: collection.covers
    )
  }
}
