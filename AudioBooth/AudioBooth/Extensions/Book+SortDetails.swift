import API
import Foundation
import Models

extension Book {
  func sortDetails(for sortBy: SortBy?, time: Date.FormatStyle.TimeStyle) -> String? {
    switch sortBy {
    case .publishedYear:
      return publishedYear.map({ "Published \($0)" })
    case .title, .authorName, .authorNameLF:
      return nil
    case .addedAt:
      return "Added \(addedAt.formatted(date: .numeric, time: time))"
    case .updatedAt:
      return "Updated \(updatedAt.formatted(date: .numeric, time: time))"
    case .size:
      return size.map { "Size \($0.formatted(.byteCount(style: .file)))" }
    case .duration:
      return Duration.seconds(duration).formatted(
        .units(allowed: [.hours, .minutes, .seconds], width: .narrow)
      )
    case .progress:
      if let mediaProgress = try? MediaProgress.fetch(bookID: id) {
        return "Progress: \(mediaProgress.lastUpdate.formatted(date: .numeric, time: time))"
      } else {
        return nil
      }
    case .progressFinishedAt:
      if let mediaProgress = try? MediaProgress.fetch(bookID: id), mediaProgress.isFinished {
        let date = mediaProgress.finishedAt ?? mediaProgress.lastUpdate
        return "Finished \(date.formatted(date: .numeric, time: time))"
      } else {
        return nil
      }
    case .progressCreatedAt:
      if let mediaProgress = try? MediaProgress.fetch(bookID: id) {
        return "Started \(mediaProgress.lastPlayedAt.formatted(date: .numeric, time: time))"
      } else {
        return nil
      }
    default:
      return nil
    }
  }
}
