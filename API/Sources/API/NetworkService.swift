import Foundation
import Logging
import Pulse

enum HTTPMethod: String {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"
}

enum NetworkError: LocalizedError {
  case httpError(statusCode: Int, message: String?)
  case invalidResponse
  case decodingError(Error)

  var errorDescription: String? {
    switch self {
    case .httpError(let statusCode, let message):
      switch statusCode {
      case 401:
        return "Invalid username or password. Please check your credentials and try again."
      case 403:
        return "Access forbidden. Please check your credentials."
      case 404:
        return "Server not found. Please check the server URL and try again."
      case 500...599:
        return "Server error. Please try again later or contact your server administrator."
      default:
        return message ?? "HTTP error \(statusCode)"
      }
    case .invalidResponse:
      return "Invalid server response"
    case .decodingError(let error):
      return "Failed to decode server response: \(error.localizedDescription)"
    }
  }
}

struct NetworkRequest<T: Decodable> {
  let path: String
  let method: HTTPMethod
  let body: (any Encodable)?
  let query: [String: String]?
  let headers: [String: String]?
  let timeout: TimeInterval?
  let discretionary: Bool

  init(
    path: String,
    method: HTTPMethod = .get,
    body: (any Encodable)? = nil,
    query: [String: String]? = nil,
    headers: [String: String]? = nil,
    timeout: TimeInterval? = nil,
    discretionary: Bool = false
  ) {
    self.path = path
    self.method = method
    self.body = body
    self.query = query
    self.headers = headers
    self.timeout = timeout
    self.discretionary = discretionary
  }
}

struct NetworkResponse<T: Decodable> {
  let value: T
}

final class NetworkService {
  private let baseURL: URL
  private let headersProvider: () async -> [String: String]
  private weak var server: Server?

  private let session: URLSessionProtocol = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 60

    #if os(watchOS)
    config.timeoutIntervalForResource = 300
    config.allowsExpensiveNetworkAccess = true
    config.allowsConstrainedNetworkAccess = true
    config.allowsCellularAccess = true
    #endif

    return URLSessionProxy(configuration: config)
  }()

  private let discretionarySession: URLSessionProtocol = {
    let discretionaryConfig = URLSessionConfiguration.default
    discretionaryConfig.timeoutIntervalForRequest = 30
    discretionaryConfig.timeoutIntervalForResource = 60

    #if os(watchOS)
    discretionaryConfig.timeoutIntervalForResource = 300
    discretionaryConfig.allowsExpensiveNetworkAccess = true
    discretionaryConfig.allowsConstrainedNetworkAccess = true
    discretionaryConfig.allowsCellularAccess = true
    discretionaryConfig.waitsForConnectivity = true
    #endif

    #if os(iOS)
    discretionaryConfig.sessionSendsLaunchEvents = true
    discretionaryConfig.isDiscretionary = true
    discretionaryConfig.shouldUseExtendedBackgroundIdleMode = true
    #endif

    return URLSessionProxy(configuration: discretionaryConfig)
  }()

  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let timestamp = try container.decode(Int64.self)
      return Date(timeIntervalSince1970: TimeInterval(timestamp / 1000))
    }
    return decoder
  }()

  init(
    baseURL: URL,
    server: Server? = nil,
    headersProvider: @escaping () async -> [String: String] = { [:] }
  ) {
    self.baseURL = baseURL
    self.server = server
    self.headersProvider = headersProvider
  }

  func send<T: Decodable>(_ request: NetworkRequest<T>) async throws -> NetworkResponse<T> {
    let urlRequest = try await buildURLRequest(from: request)

    AppLogger.network.info(
      "Sending \(urlRequest.httpMethod ?? "GET") request to: \(urlRequest.url?.redactedString ?? "unknown")"
    )

    let selectedSession = request.discretionary ? discretionarySession : session

    do {
      let (data, response) = try await selectedSession.data(for: urlRequest)

      guard let httpResponse = response as? HTTPURLResponse else {
        AppLogger.network.error("Received non-HTTP response")
        server?.status = .connectionError
        throw NetworkError.invalidResponse
      }

      guard 200...299 ~= httpResponse.statusCode else {
        let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
        AppLogger.network.error(
          "HTTP \(httpResponse.statusCode) error. Response body: \(responseBody)"
        )

        if httpResponse.statusCode == 401 {
          server?.status = .authenticationError
        } else {
          server?.status = .connectionError
        }

        throw NetworkError.httpError(statusCode: httpResponse.statusCode, message: responseBody)
      }

      server?.status = .connected

      let decodedValue: T
      if T.self == Data.self {
        decodedValue = data as! T
      } else if data.isEmpty {
        throw NetworkError.decodingError(URLError(.cannotDecodeContentData))
      } else {
        do {
          decodedValue = try decoder.decode(T.self, from: data)
        } catch {
          AppLogger.network.error(
            "Failed to decode \(T.self): \(error)"
          )

          if let decodingError = error as? DecodingError {
            switch decodingError {
            case .keyNotFound(let key, let context):
              AppLogger.network.error(
                "  Missing key: '\(key.stringValue)' at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
              )
            case .typeMismatch(let type, let context):
              AppLogger.network.error(
                "  Type mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
              )
              AppLogger.network.error("  Context: \(context.debugDescription)")
            case .valueNotFound(let type, let context):
              AppLogger.network.error(
                "  Value not found: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
              )
              AppLogger.network.error("  Context: \(context.debugDescription)")
            case .dataCorrupted(let context):
              AppLogger.network.error(
                "  Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
              )
              AppLogger.network.error("  Context: \(context.debugDescription)")
            @unknown default:
              AppLogger.network.error("  Unknown decoding error")
            }
          }

          throw NetworkError.decodingError(error)
        }
      }
      return NetworkResponse(value: decodedValue)
    } catch {
      if let urlError = error as? URLError {
        AppLogger.network.error("Network request failed: \(urlError.localizedDescription)")
        server?.status = .connectionError
      }
      throw error
    }
  }

  private func buildURLRequest<T: Decodable>(
    from request: NetworkRequest<T>
  ) async throws
    -> URLRequest
  {
    var url = baseURL.appendingPathComponent(request.path)

    if let query = request.query {
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
      if let updatedURL = components?.url {
        url = updatedURL
      }
    }

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = request.method.rawValue
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

    for (key, value) in await headersProvider() {
      urlRequest.setValue(value, forHTTPHeaderField: key)
    }

    if let headers = request.headers {
      for (key, value) in headers {
        urlRequest.setValue(value, forHTTPHeaderField: key)
      }
    }

    if let timeout = request.timeout {
      urlRequest.timeoutInterval = timeout
    }

    if let body = request.body {
      urlRequest.httpBody = try JSONEncoder().encode(body)
    }

    return urlRequest
  }
}

extension URL {
  public var redactedString: String {
    var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
    components?.host = "abs.invalid"
    components?.port = nil
    return components?.string ?? relativePath
  }
}
