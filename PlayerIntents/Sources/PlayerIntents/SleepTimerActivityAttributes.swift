import Foundation
import SwiftUI
import UIKit

#if !targetEnvironment(macCatalyst)
import ActivityKit
#endif

#if !targetEnvironment(macCatalyst)
public struct SleepTimerActivityAttributes: ActivityAttributes {
  public enum TimerDisplay: Codable, Hashable {
    case countdown(Date)
    case paused(TimeInterval)
  }

  public struct ContentState: Codable, Hashable {
    public var timer: TimerDisplay
    private var accentColorRaw: String?

    public init(timer: TimerDisplay, accentColor: Color? = nil) {
      self.timer = timer
      self.accentColorRaw = accentColor?.rawValue
    }

    public var accentColor: Color? {
      guard let raw = accentColorRaw else { return nil }
      return Color(rawValue: raw)
    }
  }

  public init() {}
}
#endif

extension Color: @retroactive RawRepresentable {
  public init?(rawValue: String) {
    guard
      let data = Data(base64Encoded: rawValue),
      let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data)
    else {
      return nil
    }
    self = Color(color)
  }

  public var rawValue: String {
    guard let data = try? NSKeyedArchiver.archivedData(withRootObject: UIColor(self), requiringSecureCoding: false)
    else {
      return ""
    }
    return data.base64EncodedString()
  }
}
