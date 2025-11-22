import Foundation

public struct ListeningStats: Codable {
  public let totalTime: Double
  public let days: [String: Double]
  public let dayOfWeek: [String: Double]
  public let today: Double
}
