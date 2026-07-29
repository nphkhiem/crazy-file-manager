protocol FileSystemScanning: Sendable {
  func batches(
    for scope: ScanScope
  ) async -> AsyncThrowingStream<FileSystemScanBatch, Error>
}
