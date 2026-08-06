import Foundation

@testable import CrazyFileManager

actor SyntheticFileSystemScanner: FileSystemScanning {
  private let totalItemCount: Int
  private let scopeURL: URL
  private let batchSize: Int
  private(set) var generatedItemCount = 0
  private var activeStreamID: UUID?

  init(totalItemCount: Int, scopeURL: URL, batchSize: Int = 128) {
    self.totalItemCount = totalItemCount
    self.scopeURL = scopeURL
    self.batchSize = batchSize
  }

  func batches(
    for scope: ScanScope
  ) async -> AsyncThrowingStream<FileSystemScanBatch, Error> {
    let streamID = UUID()
    activeStreamID = streamID
    generatedItemCount = 0
    return AsyncThrowingStream {
      try await self.nextBatch(for: streamID)
    }
  }

  private func nextBatch(for streamID: UUID) async throws -> FileSystemScanBatch? {
    try Task.checkCancellation()
    guard activeStreamID == streamID else {
      throw CancellationError()
    }
    guard generatedItemCount < totalItemCount else {
      return nil
    }

    let remaining = totalItemCount - generatedItemCount
    let countThisBatch = min(batchSize, remaining)
    var items: [ScannedItem] = []
    items.reserveCapacity(countThisBatch)
    for offset in 0..<countThisBatch {
      items.append(Self.item(at: generatedItemCount + offset, scopeURL: scopeURL))
    }
    generatedItemCount += countThisBatch

    return FileSystemScanBatch(
      items: items,
      issues: [],
      progress: ScanProgress(
        discoveredItemCount: generatedItemCount,
        issueCount: 0,
        currentArea: scopeURL
      )
    )
  }

  private static func item(at index: Int, scopeURL: URL) -> ScannedItem {
    let name = "item-\(index).bin"
    let location = scopeURL.appending(path: name)
    return ScannedItem(
      id: UUID(),
      parentPath: scopeURL.path(percentEncoded: false),
      location: location,
      name: name,
      kind: .file,
      diskUsedBytes: 4_096,
      apparentSizeBytes: 4_096,
      isHidden: false,
      isCloudOnly: false,
      fileSystemIdentity: nil,
      hardLinkCount: 1,
      modifiedAt: nil
    )
  }
}
