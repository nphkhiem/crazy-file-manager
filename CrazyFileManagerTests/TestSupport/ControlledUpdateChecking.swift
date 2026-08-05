import Foundation

@testable import CrazyFileManager

final class ControlledUpdateChecking: UpdateChecking, @unchecked Sendable {
  private let lock = NSLock()
  private var result: Result<Data, Error>
  private(set) var fetchCallCount = 0
  private(set) var lastRequestedURL: URL?

  init(result: Result<Data, Error> = .success(Data())) {
    self.result = result
  }

  func setResult(_ result: Result<Data, Error>) {
    lock.withLock { self.result = result }
  }

  func fetchMetadataEnvelope(from url: URL) async throws -> Data {
    let currentResult = lock.withLock { () -> Result<Data, Error> in
      fetchCallCount += 1
      lastRequestedURL = url
      return result
    }
    return try currentResult.get()
  }
}
