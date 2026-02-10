import Foundation

public protocol CollectionLike {
  var id: String { get }
  var name: String { get }
  var libraryID: String { get }
  var description: String? { get }
  var books: [Book] { get }
  var itemCount: Int { get }
  var covers: [URL] { get }
  var lastUpdate: Date { get }
  var createdAt: Date { get }
}
