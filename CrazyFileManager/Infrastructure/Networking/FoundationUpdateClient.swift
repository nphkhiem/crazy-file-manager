import Foundation

final class FoundationUpdateClient: UpdateChecking, @unchecked Sendable {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func fetchMetadataEnvelope(from url: URL) async throws -> Data {
    let (data, _) = try await session.data(from: url)
    return data
  }
}
