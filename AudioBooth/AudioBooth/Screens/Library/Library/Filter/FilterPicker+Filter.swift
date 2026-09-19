import Foundation

extension FilterPicker.Model {
  enum Filter: Equatable {
    case all
    case explicit
    case abridged
    case progress(String)
    case series(String, String)
    case authors(String, String)
    case narrators(String)
    case genres(String)
    case tags(String)
    case languages(String)
    case publishers(String)
    case publishedDecades(String)
    case tracks(Tracks)
    case ebooks(Ebooks)
  }
}

extension FilterPicker.Model.Filter {
  enum Tracks: String, CaseIterable {
    case noTracks = "none"
    case single
    case multi

    var title: String {
      switch self {
      case .noTracks: String(localized: "No Tracks")
      case .single: String(localized: "Single Track")
      case .multi: String(localized: "Multi Track")
      }
    }
  }

  enum Ebooks: String, CaseIterable {
    case ebook
    case noEbook = "no-ebook"
    case supplementary
    case noSupplementary = "no-supplementary"

    var title: String {
      switch self {
      case .ebook: String(localized: "Has Ebook")
      case .noEbook: String(localized: "Missing Ebook")
      case .supplementary: String(localized: "Has Supplementary Ebook")
      case .noSupplementary: String(localized: "Missing Supplementary Ebook")
      }
    }
  }
}

extension FilterPicker.Model.Filter {
  var title: String? {
    switch self {
    case .all: nil
    case .explicit: "Explicit"
    case .abridged: "Abridged"
    case .progress(let name): name
    case .authors(_, let name): name
    case .series(_, let name): name
    case .narrators(let name): name
    case .genres(let name): name
    case .tags(let name): name
    case .languages(let name): name
    case .publishers(let name): name
    case .publishedDecades(let decade): decade
    case .tracks(let tracks): tracks.title
    case .ebooks(let ebooks): ebooks.title
    }
  }

  var queryValue: String? {
    switch self {
    case .all:
      return nil
    case .explicit:
      return "explicit"
    case .abridged:
      return "abridged"
    case .progress(let name):
      let id = name.lowercased().replacingOccurrences(of: " ", with: "-")
      return "progress.\(Data(id.utf8).base64EncodedString())"
    case .series(let id, _):
      return "series.\(Data(id.utf8).base64EncodedString())"
    case .authors(let id, _):
      return "authors.\(Data(id.utf8).base64EncodedString())"
    case .narrators(let name):
      return "narrators.\(Data(name.utf8).base64EncodedString())"
    case .genres(let name):
      return "genres.\(Data(name.utf8).base64EncodedString())"
    case .tags(let name):
      return "tags.\(Data(name.utf8).base64EncodedString())"
    case .languages(let name):
      return "languages.\(Data(name.utf8).base64EncodedString())"
    case .publishers(let name):
      return "publishers.\(Data(name.utf8).base64EncodedString())"
    case .publishedDecades(let decade):
      return "publishedDecades.\(Data(decade.utf8).base64EncodedString())"
    case .tracks(let tracks):
      return "tracks.\(Data(tracks.rawValue.utf8).base64EncodedString())"
    case .ebooks(let ebooks):
      return "ebooks.\(Data(ebooks.rawValue.utf8).base64EncodedString())"
    }
  }
}

extension FilterPicker.Model.Filter: RawRepresentable, Codable {
  enum CodingKeys: String, CodingKey {
    case type
    case value1
    case value2
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)

    switch type {
    case "all":
      self = .all
    case "explicit":
      self = .explicit
    case "abridged":
      self = .abridged
    case "progress":
      let value = try container.decode(String.self, forKey: .value1)
      self = .progress(value)
    case "series":
      let id = try container.decode(String.self, forKey: .value1)
      let name = try container.decode(String.self, forKey: .value2)
      self = .series(id, name)
    case "authors":
      let id = try container.decode(String.self, forKey: .value1)
      let name = try container.decode(String.self, forKey: .value2)
      self = .authors(id, name)
    case "narrators":
      let value = try container.decode(String.self, forKey: .value1)
      self = .narrators(value)
    case "genres":
      let value = try container.decode(String.self, forKey: .value1)
      self = .genres(value)
    case "tags":
      let value = try container.decode(String.self, forKey: .value1)
      self = .tags(value)
    case "languages":
      let value = try container.decode(String.self, forKey: .value1)
      self = .languages(value)
    case "publishers":
      let value = try container.decode(String.self, forKey: .value1)
      self = .publishers(value)
    case "publishedDecades":
      let value = try container.decode(String.self, forKey: .value1)
      self = .publishedDecades(value)
    case "tracks":
      let value = try container.decode(String.self, forKey: .value1)
      guard let tracks = Tracks(rawValue: value) else {
        throw DecodingError.dataCorruptedError(
          forKey: .value1,
          in: container,
          debugDescription: "Unknown tracks filter value"
        )
      }
      self = .tracks(tracks)
    case "ebooks":
      let value = try container.decode(String.self, forKey: .value1)
      guard let ebooks = Ebooks(rawValue: value) else {
        throw DecodingError.dataCorruptedError(
          forKey: .value1,
          in: container,
          debugDescription: "Unknown ebooks filter value"
        )
      }
      self = .ebooks(ebooks)
    default:
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Unknown filter type"
        )
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    switch self {
    case .all:
      try container.encode("all", forKey: .type)
    case .explicit:
      try container.encode("explicit", forKey: .type)
    case .abridged:
      try container.encode("abridged", forKey: .type)
    case .progress(let value):
      try container.encode("progress", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .series(let id, let name):
      try container.encode("series", forKey: .type)
      try container.encode(id, forKey: .value1)
      try container.encode(name, forKey: .value2)
    case .authors(let id, let name):
      try container.encode("authors", forKey: .type)
      try container.encode(id, forKey: .value1)
      try container.encode(name, forKey: .value2)
    case .narrators(let value):
      try container.encode("narrators", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .genres(let value):
      try container.encode("genres", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .tags(let value):
      try container.encode("tags", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .languages(let value):
      try container.encode("languages", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .publishers(let value):
      try container.encode("publishers", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .publishedDecades(let value):
      try container.encode("publishedDecades", forKey: .type)
      try container.encode(value, forKey: .value1)
    case .tracks(let value):
      try container.encode("tracks", forKey: .type)
      try container.encode(value.rawValue, forKey: .value1)
    case .ebooks(let value):
      try container.encode("ebooks", forKey: .type)
      try container.encode(value.rawValue, forKey: .value1)
    }
  }

  public init?(rawValue: String) {
    guard let data = rawValue.data(using: .utf8),
      let result = try? JSONDecoder().decode(FilterPicker.Model.Filter.self, from: data)
    else {
      return nil
    }
    self = result
  }

  public var rawValue: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    guard let data = try? encoder.encode(self),
      let result = String(data: data, encoding: .utf8)
    else {
      return ""
    }
    return result
  }
}
