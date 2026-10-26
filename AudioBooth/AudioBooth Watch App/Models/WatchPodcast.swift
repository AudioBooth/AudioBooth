import Foundation

struct WatchPodcast: Hashable {
  let id: String
  let title: String
  let author: String?
  let coverURL: URL?

  init?(dictionary: [String: Any]) {
    guard let id = dictionary["id"] as? String,
      let title = dictionary["title"] as? String
    else {
      return nil
    }

    self.id = id
    self.title = title
    self.author = dictionary["author"] as? String
    self.coverURL = (dictionary["coverURL"] as? String).flatMap { URL(string: $0) }
  }
}
