import Foundation

@testable import CrazyFileManager

final class ControlledUpdateArtifactDownloading: UpdateArtifactDownloading, @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<URL, Error>
  private(set) var downloadCallCount = 0
  private(set) var lastRequestedURL: URL?

  init(result: Result<URL, Error>) {
    self.result = result
  }

  func setResult(_ result: Result<URL, Error>) {
    lock.withLock { self.result = result }
  }

  func download(from url: URL) async throws -> URL {
    let currentResult = lock.withLock { () -> Result<URL, Error> in
      downloadCallCount += 1
      lastRequestedURL = url
      return result
    }
    return try currentResult.get()
  }
}
