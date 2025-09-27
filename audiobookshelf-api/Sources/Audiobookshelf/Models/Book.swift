import Foundation

public struct Book: Codable, Sendable {
  public let id: String
  public let libraryID: String
  public let title: String
  public let duration: Double
  public let media: Media
  public let authorName: String?
  public let publishedYear: String?
  public let size: Int?
  public let addedAt: Date
  public let updatedAt: Date
  public let sequence: String?

  public var coverURL: URL? {
    guard let serverURL = Audiobookshelf.shared.serverURL else { return nil }
    var url = serverURL.appendingPathComponent("audiobookshelf/api/items/\(id)/cover")
    url.append(queryItems: [URLQueryItem(name: "raw", value: "1")])
    return url
  }

  public var numAudioFiles: Int {
    switch media {
    case .audiobook(let numFiles):
      return numFiles
    case .ebook:
      return 0
    }
  }

  public var ebookURL: URL? {
    guard let serverURL = Audiobookshelf.shared.serverURL,
      let token = Audiobookshelf.shared.authentication.connection?.token
    else { return nil }

    var url = serverURL.appendingPathComponent("api/items/\(id)/ebook")
    url.append(queryItems: [URLQueryItem(name: "token", value: token)])
    return url
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case libraryId
    case media
    case addedAt
    case updatedAt
  }

  private enum MediaKeys: String, CodingKey {
    case metadata
    case duration
    case numAudioFiles
    case ebookFormat
    case size
  }

  private enum MetadataKeys: String, CodingKey {
    case title
    case authorName
    case series
    case publishedYear
  }

  private enum SeriesKeys: String, CodingKey {
    case sequence
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    self.id = try container.decode(String.self, forKey: .id)
    self.libraryID = try container.decode(String.self, forKey: .libraryId)

    let addedAtMs = try container.decode(Int.self, forKey: .addedAt)
    self.addedAt = Date(timeIntervalSince1970: TimeInterval(addedAtMs) / 1000.0)

    let updatedAtMs = try container.decode(Int.self, forKey: .updatedAt)
    self.updatedAt = Date(timeIntervalSince1970: TimeInterval(updatedAtMs) / 1000.0)

    let mediaContainer = try container.nestedContainer(keyedBy: MediaKeys.self, forKey: .media)
    self.duration = try mediaContainer.decodeIfPresent(Double.self, forKey: .duration) ?? 0

    let metadataContainer = try mediaContainer.nestedContainer(
      keyedBy: MetadataKeys.self, forKey: .metadata)
    self.title = try metadataContainer.decode(String.self, forKey: .title)

    let numAudioFiles = try mediaContainer.decodeIfPresent(Int.self, forKey: .numAudioFiles) ?? 0
    let ebookFormat = try mediaContainer.decodeIfPresent(String.self, forKey: .ebookFormat)

    if numAudioFiles > 0 {
      self.media = .audiobook(numFiles: numAudioFiles)
    } else if let format = ebookFormat {
      self.media = .ebook(format: format)
    } else {
      self.media = .audiobook(numFiles: 0)
    }
    self.authorName = try metadataContainer.decodeIfPresent(String.self, forKey: .authorName)
    self.publishedYear = try metadataContainer.decodeIfPresent(String.self, forKey: .publishedYear)
    self.size = try mediaContainer.decodeIfPresent(Int.self, forKey: .size)

    let seriesContainer = try? metadataContainer.nestedContainer(
      keyedBy: SeriesKeys.self, forKey: .series)
    self.sequence = try seriesContainer?.decodeIfPresent(String.self, forKey: .sequence)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(libraryID, forKey: .libraryId)
    try container.encode(Int(addedAt.timeIntervalSince1970 * 1000), forKey: .addedAt)
    try container.encode(Int(updatedAt.timeIntervalSince1970 * 1000), forKey: .updatedAt)

    var mediaContainer = container.nestedContainer(keyedBy: MediaKeys.self, forKey: .media)
    try mediaContainer.encode(duration, forKey: .duration)

    switch media {
    case .audiobook(let numFiles):
      try mediaContainer.encode(numFiles, forKey: .numAudioFiles)
    case .ebook(let format):
      try mediaContainer.encode(0, forKey: .numAudioFiles)
      try mediaContainer.encode(format, forKey: .ebookFormat)
    }

    try mediaContainer.encodeIfPresent(size, forKey: .size)

    var metadataContainer = mediaContainer.nestedContainer(
      keyedBy: MetadataKeys.self, forKey: .metadata)
    try metadataContainer.encode(title, forKey: .title)
    try metadataContainer.encodeIfPresent(authorName, forKey: .authorName)
    try metadataContainer.encodeIfPresent(publishedYear, forKey: .publishedYear)

    if let sequence = sequence {
      var seriesContainer = metadataContainer.nestedContainer(
        keyedBy: SeriesKeys.self, forKey: .series)
      try seriesContainer.encode(sequence, forKey: .sequence)
    }
  }
}

extension Book {
  public enum Media: Codable, Sendable {
    case audiobook(numFiles: Int)
    case ebook(format: String)
  }
}
