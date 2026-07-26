import Combine
import CoreNFC

class NFCWriter: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {
  private var session: NFCNDEFReaderSession?
  private var continuation: CheckedContinuation<Void, Never>?

  private let bookID: String

  private init(bookID: String) async {
    self.bookID = bookID

    super.init()

    await withCheckedContinuation { continuation in
      self.continuation = continuation
      session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
      session?.alertMessage = "Hold your iPhone near the tag."
      session?.begin()
    }
  }

  static func write(bookID: String) async {
    _ = await NFCWriter(bookID: bookID)
  }

  func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

  func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
    guard let tag = tags.first else { return }

    if tags.count > 1 {
      let retryInterval = DispatchTimeInterval.milliseconds(500)
      session.alertMessage = "Detected more than 1 tag. Please try again."
      DispatchQueue.global().asyncAfter(
        deadline: .now() + retryInterval,
        execute: {
          session.restartPolling()
        }
      )
      return
    }

    Task {
      do {
        try await session.connect(to: tag)

        do {
          let (status, _) = try await tag.queryNDEFStatus()

          switch status {
          case .notSupported:
            session.alertMessage = "Tag is not NDEF compliant."

          case .readOnly:
            session.alertMessage = "Read only tag detected."

          case .readWrite:
            let payload = NFCNDEFPayload.wellKnownTypeURIPayload(
              string: "audiobooth://play/\(bookID)"
            )
            let message = NFCNDEFMessage(records: [payload].compactMap(\.self))

            do {
              try await tag.writeNDEF(message)
              session.alertMessage = "Write book to tag successful."
            } catch {
              session.alertMessage = "Write to tag fail: \(error)"
            }

          @unknown default:
            session.alertMessage = "Unknown tag status."
          }
        } catch {
          session.alertMessage = "Unable to query the status of tag."
        }
      } catch {
        session.alertMessage = "Unable to connect to tag."
      }

      session.invalidate()
    }
  }

  func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}

  func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
    continuation?.resume()
    continuation = nil
  }
}
