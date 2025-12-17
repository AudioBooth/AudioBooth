import Foundation
import Logging
import Pulse
import PulseLogHandler

enum AppLogger {
  static let session = Logger(label: "session")
  static let network = Logger(label: "network")
  static let watchConnectivity = Logger(label: "watch-connectivity")
  static let player = Logger(label: "player")
  static let download = Logger(label: "download")
  static let viewModel = Logger(label: "viewModel")
  static let persistence = Logger(label: "persistence")
  static let general = Logger(label: "general")
  static let authentication = Logger(label: "authentication")

  static func bootstrap() {
    configureNetworkLogger()

    LoggingSystem.bootstrap { label in
      MultiplexLogHandler([
        StreamLogHandler.standardOutput(label: label),
        PersistentLogHandler(label: label),
      ])
    }
  }

  private static func configureNetworkLogger() {
    NetworkLogger.shared = NetworkLogger { config in
      config.sensitiveHeaders = ["Authorization", "x-refresh-token"]
      config.sensitiveQueryItems = ["token"]
      config.sensitiveDataFields = [
        "accessToken",
        "authOpenIDAuthorizationURL",
        "authOpenIDIssuerURL",
        "authOpenIDJwksURL",
        "authOpenIDLogoutURL",
        "authOpenIDTokenURL",
        "authOpenIDUserInfoURL",
        "email",
        "refreshToken",
        "token",
      ]
      config.willHandleEvent = { $0.redacted }
    }
  }
}

extension LoggerStore.Event {
  nonisolated var redacted: Self {
    switch self {
    case .messageStored, .networkTaskProgressUpdated:
      return self
    case .networkTaskCreated(let event):
      var event = event
      event.originalRequest = event.originalRequest.redacted
      event.currentRequest = event.currentRequest?.redacted
      return .networkTaskCreated(event)
    case .networkTaskCompleted(let event):
      var event = event
      event.originalRequest = event.originalRequest.redacted
      event.currentRequest = event.currentRequest?.redacted
      return .networkTaskCompleted(event)
    }
  }
}

extension NetworkLogger.Request {
  nonisolated var redacted: Self {
    var copy = self
    copy.url = url?.redacted
    return copy
  }
}

extension URL {
  nonisolated var redacted: Self {
    var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
    components?.host = "abs.invalid"
    components?.port = nil
    return components?.url ?? self
  }

}
