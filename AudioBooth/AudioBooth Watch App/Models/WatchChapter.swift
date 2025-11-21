import Foundation

struct WatchChapter: Codable, Identifiable {
  let id: Int
  let title: String
  let start: Double
  let end: Double

  var duration: Double {
    end - start
  }

  init(id: Int, title: String, start: Double, end: Double) {
    self.id = id
    self.title = title
    self.start = start
    self.end = end
  }

  init?(dictionary: [String: Any]) {
    guard let id = dictionary["id"] as? Int,
      let title = dictionary["title"] as? String,
      let start = dictionary["start"] as? Double,
      let end = dictionary["end"] as? Double
    else {
      return nil
    }

    self.id = id
    self.title = title
    self.start = start
    self.end = end
  }
}
