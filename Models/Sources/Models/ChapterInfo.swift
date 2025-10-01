import Audiobookshelf
import Foundation
import SwiftData

@Model
public final class ChapterInfo {
  public var id: Int
  public var start: TimeInterval
  public var end: TimeInterval
  public var title: String

  public init(from chapter: PlaySession.Chapter) {
    self.id = chapter.id
    self.start = chapter.start
    self.end = chapter.end
    self.title = chapter.title
  }
}
