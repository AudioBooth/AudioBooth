import Foundation

struct WatchTrack: Codable {
  let index: Int
  let duration: Double
  let size: Int64?
  let ext: String?
  var url: URL?
  var relativePath: String?
}
