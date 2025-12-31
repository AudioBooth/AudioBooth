import API
import Foundation
import Models

final class ItemRowModel: ItemRow.Model {
  init(_ book: Book) {
    super.init(
      id: book.id,
      title: book.title,
      details: book.authorName,
      coverURL: book.coverURL()
    )
  }

  override func onAppear() {
    progress = MediaProgress.progress(for: id)
  }
}
