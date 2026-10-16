import API
import Foundation
import Logging

final class NarrationProbe {
  static let shared = NarrationProbe()

  private var audioSizes: [String: Int64?] = [:]

  func audioSize(of book: Book) async -> Int64? {
    guard !book.mediaType.contains(.audiobook),
      let ebookFile = book.media.ebookFile,
      ebookFile.metadata.ext.lowercased() == ".epub"
    else {
      return nil
    }

    let key = "\(book.id)/\(ebookFile.ino)"
    if let cached = audioSizes[key] {
      return cached
    }

    guard let url = book.ebookURL,
      let server = Audiobookshelf.shared.authentication.server,
      let credentials = try? await server.freshToken
    else {
      return nil
    }

    let request = DownloadManager.shared.authorizedRequest(url: url, credentials: credentials)

    do {
      let audioSize = try await RemoteEPUBDirectory(request: request).audioSize()
      audioSizes[key] = audioSize
      return audioSize
    } catch {
      AppLogger.download.warning("Narration probe failed for \(book.id): \(error)")
      return nil
    }
  }
}

private nonisolated struct RemoteEPUBDirectory {
  enum Failure: Error {
    case rangeNotSupported
    case invalidArchive
  }

  private static let tailLength = 65_536
  private static let maximumDirectoryLength: Int64 = 16_777_216
  private static let endOfDirectorySignature = Data([0x50, 0x4B, 0x05, 0x06])
  private static let entrySignature: UInt32 = 0x0201_4B50
  private static let audioExtensions: Set<String> = ["aac", "m4a", "m4b", "mp3", "mp4", "wav"]

  let request: URLRequest

  @concurrent
  func audioSize() async throws -> Int64? {
    let (tail, totalLength) = try await fetch(range: "bytes=-\(Self.tailLength)")
    let tailStart = totalLength - Int64(tail.count)

    guard tailStart >= 0,
      let end = tail.range(of: Self.endOfDirectorySignature, options: .backwards)?.lowerBound,
      end + 22 <= tail.count
    else {
      throw Failure.invalidArchive
    }

    let count = Int64(Self.integer(UInt16.self, in: tail, at: end + 10))
    let size = Int64(Self.integer(UInt32.self, in: tail, at: end + 12))
    let offset = Int64(Self.integer(UInt32.self, in: tail, at: end + 16))

    guard size > 0, size <= Self.maximumDirectoryLength, offset <= totalLength - size else {
      throw Failure.invalidArchive
    }

    let directory: Data
    if offset >= tailStart, Int(offset - tailStart + size) <= tail.count {
      let start = Int(offset - tailStart)
      directory = tail.subdata(in: start..<start + Int(size))
    } else {
      directory = try await fetch(range: "bytes=\(offset)-\(offset + size - 1)").data
    }

    return try Self.audioSize(in: directory, count: count)
  }

  private static func audioSize(in directory: Data, count: Int64) throws -> Int64? {
    var position = 0
    var hasSMIL = false
    var audioSize: Int64 = 0

    for _ in 0..<count {
      guard position + 46 <= directory.count,
        integer(UInt32.self, in: directory, at: position) == entrySignature
      else {
        throw Failure.invalidArchive
      }

      let compressedSize = Int64(integer(UInt32.self, in: directory, at: position + 20))
      let nameLength = Int(integer(UInt16.self, in: directory, at: position + 28))
      let extraLength = Int(integer(UInt16.self, in: directory, at: position + 30))
      let commentLength = Int(integer(UInt16.self, in: directory, at: position + 32))

      guard position + 46 + nameLength <= directory.count else { throw Failure.invalidArchive }

      let name = String(decoding: directory.subdata(in: position + 46..<position + 46 + nameLength), as: UTF8.self)
      let pathExtension = (name as NSString).pathExtension.lowercased()

      if pathExtension == "smil" {
        hasSMIL = true
      } else if audioExtensions.contains(pathExtension) {
        audioSize += compressedSize
      }

      position += 46 + nameLength + extraLength + commentLength
    }

    return hasSMIL && audioSize > 0 ? audioSize : nil
  }

  private func fetch(range: String) async throws -> (data: Data, totalLength: Int64) {
    var request = request
    request.setValue(range, forHTTPHeaderField: "Range")

    let (bytes, response) = try await URLSession.shared.bytes(for: request)

    guard let response = response as? HTTPURLResponse,
      response.statusCode == 206,
      let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
      let totalLength = contentRange.split(separator: "/").last.flatMap({ Int64($0) })
    else {
      bytes.task.cancel()
      throw Failure.rangeNotSupported
    }

    var data = Data()
    data.reserveCapacity(max(0, Int(response.expectedContentLength)))
    for try await byte in bytes {
      data.append(byte)
    }
    return (data, totalLength)
  }

  private static func integer<T: FixedWidthInteger>(_ type: T.Type, in data: Data, at offset: Int) -> T {
    data.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self)) }
  }
}
