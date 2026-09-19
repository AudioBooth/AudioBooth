import API
import AppIntents
import Foundation

struct ResumeLibraryEntity: AppEntity, Identifiable {
  let id: String
  let name: String

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Library"
  static var defaultQuery = ResumeLibraryQuery()

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }

  init(id: String, name: String) {
    self.id = id
    self.name = name
  }

  init(library: Library) {
    self.init(id: library.id, name: library.name)
  }
}

struct ResumeLibraryQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [ResumeLibraryEntity] {
    let libraries = await Audiobookshelf.shared.libraries.libraries
    return
      libraries
      .filter { identifiers.contains($0.id) }
      .map(ResumeLibraryEntity.init(library:))
  }

  func suggestedEntities() async throws -> [ResumeLibraryEntity] {
    let libraries = await Audiobookshelf.shared.libraries.libraries
    return libraries.map(ResumeLibraryEntity.init(library:))
  }
}
