import Foundation

protocol UpdateArtifactDownloading: Sendable {
  func download(from url: URL) async throws -> URL
}
