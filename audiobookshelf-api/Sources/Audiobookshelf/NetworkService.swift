import Foundation

enum HTTPMethod: String {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case patch = "PATCH"
  case delete = "DELETE"
}

struct NetworkRequest<T: Decodable> {
  let path: String
  let method: HTTPMethod
  let body: (any Encodable)?
  let query: [String: String]?
  let headers: [String: String]?
  let timeout: TimeInterval?

  init(
    path: String, method: HTTPMethod = .get, body: (any Encodable)? = nil,
    query: [String: String]? = nil, headers: [String: String]? = nil, timeout: TimeInterval? = nil
  ) {
    self.path = path
    self.method = method
    self.body = body
    self.query = query
    self.headers = headers
    self.timeout = timeout
  }
}

struct NetworkResponse<T: Decodable> {
  let value: T
}

final class NetworkService {
  private let baseURL: URL
  private let session: URLSession

  init(baseURL: URL, configuration: ((URLSessionConfiguration) -> Void)? = nil) {
    self.baseURL = baseURL

    let sessionConfig = URLSessionConfiguration.default
    configuration?(sessionConfig)
    self.session = URLSession(configuration: sessionConfig)
  }

  func send<T: Decodable>(_ request: NetworkRequest<T>) async throws -> NetworkResponse<T> {
    let urlRequest = try buildURLRequest(from: request)

    let (data, response) = try await session.data(for: urlRequest)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    guard 200...299 ~= httpResponse.statusCode else {
      throw URLError(.badServerResponse)
    }

    let decodedValue: T
    if T.self == Data.self {
      decodedValue = data as! T
    } else if data.isEmpty {
      throw URLError(.cannotDecodeContentData)
    } else {
      decodedValue = try JSONDecoder().decode(T.self, from: data)
    }
    return NetworkResponse(value: decodedValue)
  }

  private func buildURLRequest<T: Decodable>(from request: NetworkRequest<T>) throws -> URLRequest {
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
