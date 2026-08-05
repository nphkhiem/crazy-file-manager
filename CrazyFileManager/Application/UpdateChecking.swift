import Foundation

protocol UpdateChecking: Sendable {
  func fetchMetadataEnvelope(from url: URL) async throws -> Data
}
