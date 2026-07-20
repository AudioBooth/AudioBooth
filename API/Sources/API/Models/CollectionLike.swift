import Foundation

public protocol CollectionLike {
  var id: String { get }
  var name: String { get }
  var description: String? { get }
  var itemCount: Int { get }
  @MainActor var covers: [URL] { get }
}
