import Foundation

extension TimeInterval {
  var formattedTimeRemaining: String {
    let formatted =
      Duration.seconds(self)
      .formatted(.units(allowed: [.hours, .minutes], width: .narrow))

    return String(localized: "\(formatted) remaining")
  }
}
