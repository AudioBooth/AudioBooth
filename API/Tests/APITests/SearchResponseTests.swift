import Foundation
import Testing

@testable import API

struct SearchResponseTests {
  @Test func skipsResultsThatFailToDecode() throws {
    let json = #"""
      {
        "book": [{"libraryItem": {"unexpected": true}}],
        "authors": [
          {"id": "author-1", "name": "Ursula K. Le Guin"},
          {"name": "Missing ID"},
          {"id": "author-2", "name": "Octavia E. Butler"}
        ],
        "narrators": [{"name": "Rob Inglis", "numBooks": 3}],
        "tags": [{"name": "Favorite", "numItems": 5}],
        "genres": [{"name": "Fantasy", "numItems": 8}]
      }
      """#

    let response = try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8))

    #expect(response.book.isEmpty)
    #expect(response.authors.map(\.name) == ["Ursula K. Le Guin", "Octavia E. Butler"])
    #expect(response.narrators.map(\.name) == ["Rob Inglis"])
    #expect(response.tags.map(\.name) == ["Favorite"])
    #expect(response.genres.map(\.name) == ["Fantasy"])
  }

  @Test func missingOrMalformedSectionsAreEmpty() throws {
    let json = #"{"series": {"not": "an array"}, "authors": null}"#

    let response = try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8))

    #expect(response.book.isEmpty)
    #expect(response.podcast.isEmpty)
    #expect(response.episodes.isEmpty)
    #expect(response.series.isEmpty)
    #expect(response.authors.isEmpty)
    #expect(response.narrators.isEmpty)
    #expect(response.tags.isEmpty)
    #expect(response.genres.isEmpty)
  }
}
