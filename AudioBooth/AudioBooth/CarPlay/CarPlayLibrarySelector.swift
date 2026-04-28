import API
@preconcurrency import CarPlay
import Foundation

final class CarPlayLibrarySelector: CarPlayPageProtocol {
  let template: CPListTemplate

  init() {
    let title = String(localized: "Libraries")
    template = CPListTemplate(title: title, sections: [])
    template.tabTitle = title
    template.tabImage = UIImage(systemName: "books.vertical.fill")

    reload()
  }

  func willAppear() {
    reload()
  }

  private func reload() {
    let libraries = Audiobookshelf.shared.libraries.libraries
    let currentID = Audiobookshelf.shared.libraries.current?.id

    let items = libraries.map { library -> CPListItem in
      let detailText: String
      switch library.mediaType {
      case .book:
        detailText = String(localized: "Books")
      case .podcast:
        detailText = String(localized: "Podcasts")
      }

      let item = CPListItem(text: library.name, detailText: detailText)
      if library.id == currentID {
        item.setAccessoryImage(UIImage(systemName: "checkmark"))
      }

      item.handler = { _, completion in
        if library.id != currentID {
          Audiobookshelf.shared.libraries.current = library
        }
        completion()
      }

      return item
    }

    template.updateSections([CPListSection(items: items)])
  }
}
