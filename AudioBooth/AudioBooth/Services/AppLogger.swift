import API
import Foundation
import Logging
import Pulse
import PulseLogHandler
import UIKit

enum AppLogger {
  static let session = Logger(label: "session")
  static let watchConnectivity = Logger(label: "watch-connectivity")
  static let player = Logger(label: "player")
  static let download = Logger(label: "download")
  static let viewModel = Logger(label: "viewModel")
  static let general = Logger(label: "general")
  static let authentication = Logger(label: "authentication")
  static let crash = Logger(label: "crash")

  static func bootstrap() {
    configureNetworkLogger()

    LoggingSystem.bootstrap { label in
      var stream = StreamLogHandler.standardOutput(label: label)
      var persistent = PersistentLogHandler(label: label)

      stream.logLevel = .debug
      persistent.logLevel = .debug

      return MultiplexLogHandler([stream, RedactingLogHandler(wrapped: persistent)])
    }

    general.info("Version \(UIApplication.appVersion)")
  }

  private static func configureNetworkLogger() {
    NetworkLogger.shared = NetworkLogger { config in
      config.sensitiveHeaders = ["Authorization", "x-refresh-token", "Cookie", "Set-Cookie"]
      config.sensitiveQueryItems = ["token", "code", "code_verifier"]
      config.sensitiveDataFields = [
        "accessToken",
        "authOpenIDAuthorizationURL",
        "authOpenIDIssuerURL",
        "authOpenIDJwksURL",
        "authOpenIDLogoutURL",
        "authOpenIDTokenURL",
        "authOpenIDUserInfoURL",
        "email",
        "password",
        "refreshToken",
        "token",
        "username",
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

struct RedactingLogHandler: LogHandler {
  var wrapped: PersistentLogHandler

  var metadata: Logger.Metadata {
    get { wrapped.metadata }
    set { wrapped.metadata = newValue }
  }

  var logLevel: Logger.Level {
    get { wrapped.logLevel }
    set { wrapped.logLevel = newValue }
  }

  subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { wrapped[metadataKey: key] }
    set { wrapped[metadataKey: key] = newValue }
  }

  func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    let redacted = Logger.Message(stringLiteral: message.description.redactingURLs)
    wrapped.log(
      level: level,
      message: redacted,
      metadata: metadata,
      file: file,
      function: function,
      line: line
    )
  }

  func log(event: LogEvent) {
    let redacted = Logger.Message(stringLiteral: event.message.description.redactingURLs)
    wrapped.log(
      level: event.level,
      message: redacted,
      metadata: event.metadata,
      file: event.file,
      function: event.function,
      line: event.line
    )
  }
}

extension NetworkLogger.Request {
  nonisolated var redacted: Self {
    var copy = self
    copy.url = url?.redacted
    return copy
  }
}
