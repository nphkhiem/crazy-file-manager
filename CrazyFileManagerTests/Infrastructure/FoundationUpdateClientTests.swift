import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Foundation Update Client")
struct FoundationUpdateClientTests {
  @Test
  func givenAMetadataURL_whenFetched_thenTheRequestHasNoQueryParametersOrCustomHeaders()
    async throws
  {
    let responseBody = Data("{}".utf8)
    RecordingURLProtocol.respond(with: responseBody)
    defer { RecordingURLProtocol.reset() }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = FoundationUpdateClient(session: session)
    let url = URL(string: "https://example.com/update-metadata.json")!

    let data = try await client.fetchMetadataEnvelope(from: url)

    #expect(data == responseBody)
    let request = try #require(RecordingURLProtocol.lastRequest)
    #expect(request.url == url)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.query == nil)
    #expect(request.allHTTPHeaderFields?.keys.contains("Authorization") != true)
  }
}

private final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var responseData = Data()
  nonisolated(unsafe) private static var _lastRequest: URLRequest?

  static var lastRequest: URLRequest? {
    lock.withLock { _lastRequest }
  }

  static func respond(with data: Data) {
    lock.withLock {
      responseData = data
      _lastRequest = nil
    }
  }

  static func reset() {
    lock.withLock {
      responseData = Data()
      _lastRequest = nil
    }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    RecordingURLProtocol.lock.withLock {
      RecordingURLProtocol._lastRequest = request
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    let data = RecordingURLProtocol.lock.withLock { RecordingURLProtocol.responseData }
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
