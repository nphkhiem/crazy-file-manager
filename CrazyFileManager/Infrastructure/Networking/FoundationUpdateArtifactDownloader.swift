import Foundation

final class FoundationUpdateArtifactDownloader: UpdateArtifactDownloading, @unchecked Sendable {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func download(from url: URL) async throws -> URL {
    let (temporaryURL, _) = try await session.download(from: url)
    let downloadsDirectory = try FileManager.default.url(
      for: .downloadsDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let destinationURL = downloadsDirectory.appending(path: url.lastPathComponent)
    if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
      try FileManager.default.removeItem(at: destinationURL)
    }
    try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
    return destinationURL
  }
}
