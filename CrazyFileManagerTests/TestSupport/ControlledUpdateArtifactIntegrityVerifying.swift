import Foundation

@testable import CrazyFileManager

final class ControlledUpdateArtifactIntegrityVerifying: UpdateArtifactIntegrityVerifying,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var result: Result<String, Error>
  private(set) var verifyCallCount = 0
  private(set) var lastVerifiedURL: URL?

  init(result: Result<String, Error> = .success("expected-hash")) {
    self.result = result
  }

  func setResult(_ result: Result<String, Error>) {
    lock.withLock { self.result = result }
  }

  func sha256Hex(ofFileAt url: URL) throws -> String {
    let currentResult = lock.withLock { () -> Result<String, Error> in
      verifyCallCount += 1
      lastVerifiedURL = url
      return result
    }
    return try currentResult.get()
  }
}
