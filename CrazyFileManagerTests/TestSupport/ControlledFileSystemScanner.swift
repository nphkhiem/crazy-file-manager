@testable import CrazyFileManager

actor ControlledFileSystemScanner: FileSystemScanning {
  private(set) var requestedScopes: [ScanScope] = []
  private var continuation: AsyncThrowingStream<FileSystemScanBatch, Error>.Continuation?

  func batches(
    for scope: ScanScope
  ) async -> AsyncThrowingStream<FileSystemScanBatch, Error> {
    requestedScopes.append(scope)
    let streamAndContinuation =
      AsyncThrowingStream<FileSystemScanBatch, Error>.makeStream()
    continuation = streamAndContinuation.continuation
    return streamAndContinuation.stream
  }

  func yield(_ batch: FileSystemScanBatch) {
    continuation?.yield(batch)
  }

  func finish() {
    continuation?.finish()
  }

  func fail(_ error: any Error) {
    continuation?.finish(throwing: error)
  }
}

enum ControlledScanError: Error {
  case failed
}
