import API
import Foundation
import XCTest

final class ExportConnectionTests: XCTestCase {
  func testExportWithoutCredentialsKeepsHeadersButOmitsToken() throws {
    let connection = try makeConnection(token: .apiKey(key: "api-token"))

    let exportConnection = try XCTUnwrap(ExportConnection(connection, includeToken: false))

    XCTAssertEqual(exportConnection.headers["CF-Access-Client-Id"], "client-id")
    XCTAssertNil(exportConnection.token)
  }

  func testExportUsesActiveAlternativeURLWhenSelected() throws {
    let connection = try makeConnection(
      alternativeURL: URL(string: "https://remote.example.com")!,
      isUsingAlternativeURL: true
    )

    let exportConnection = try XCTUnwrap(ExportConnection(connection))

    XCTAssertEqual(exportConnection.url, URL(string: "https://remote.example.com"))
    XCTAssertEqual(exportConnection.alternativeURL, URL(string: "https://remote.example.com"))
    XCTAssertEqual(exportConnection.isUsingAlternativeURL, true)
  }

  func testExportWithAPIKeyCredentialsIncludesAPIKeyToken() throws {
    let connection = try makeConnection(token: .apiKey(key: "api-token"))

    let exportConnection = try XCTUnwrap(ExportConnection(connection, includeToken: true))

    XCTAssertEqual(exportConnection.token, "api-token")
    XCTAssertEqual(exportConnection.headers["CF-Access-Client-Secret"], "client-secret")
  }

  func testExportWithBearerCredentialsSharesRefreshTokenOnly() throws {
    let connection = try makeConnection(
      token: .bearer(accessToken: "access-token", refreshToken: "refresh-token", expiresAt: 123)
    )

    let exportConnection = try XCTUnwrap(ExportConnection(connection, includeToken: true))

    XCTAssertEqual(exportConnection.token, "refresh-token")
  }

  func testExportWithLegacyCredentialsCannotIncludeCredentials() throws {
    let connection = try makeConnection(token: .legacy(token: "legacy-token"))

    XCTAssertNil(ExportConnection(connection, includeToken: true))
  }

  func testExportConnectionDecodesOlderPayloadWithoutAlternativeURLFields() throws {
    let data = """
      {
        "url": "https://remote.example.com",
        "token": null,
        "headers": {
          "CF-Access-Client-Id": "client-id"
        },
        "alias": "Remote"
      }
      """.data(using: .utf8)!

    let exportConnection = try JSONDecoder().decode(ExportConnection.self, from: data)

    XCTAssertEqual(exportConnection.url, URL(string: "https://remote.example.com"))
    XCTAssertEqual(exportConnection.headers["CF-Access-Client-Id"], "client-id")
    XCTAssertNil(exportConnection.alternativeURL)
    XCTAssertNil(exportConnection.isUsingAlternativeURL)
  }

  private func makeConnection(
    token: Credentials = .apiKey(key: "api-token"),
    alternativeURL: URL? = nil,
    isUsingAlternativeURL: Bool = false
  ) throws -> Connection {
    try Connection(
      serverURL: XCTUnwrap(URL(string: "http://local.example.com")),
      token: token,
      customHeaders: [
        "CF-Access-Client-Id": "client-id",
        "CF-Access-Client-Secret": "client-secret",
      ],
      alias: "Remote",
      alternativeURL: alternativeURL,
      isUsingAlternativeURL: isUsingAlternativeURL
    )
  }
}
