import Foundation

struct FoundationFileSystemScanner: FileSystemScanning {
  private let batchSize: Int

  init(batchSize: Int = 128) {
    self.batchSize = max(1, batchSize)
  }

  func batches(
    for scope: ScanScope
  ) async -> AsyncThrowingStream<FileSystemScanBatch, Error> {
    let cursor = FoundationScanCursor(
      rootURL: scope.location,
      batchSize: batchSize
    )
    return AsyncThrowingStream {
      try Task.checkCancellation()
      return try await cursor.nextBatch()
    }
  }
}

private enum FoundationScannerError: Error {
  case scopeUnavailable
}

private actor FoundationScanCursor {
  private enum Record {
    case item(ScannedItem)
    case issue(ScanIssue)
  }

  private let rootURL: URL
  private let batchSize: Int
  private let issueBuffer = ScanIssueBuffer()
  private var enumerator: FileManager.DirectoryEnumerator?
  private var discoveredItemCount = 0
  private var issueCount = 0
  private var currentArea: URL?
  private var isFinished = false

  init(rootURL: URL, batchSize: Int) {
    self.rootURL = rootURL
    self.batchSize = batchSize
  }

  func nextBatch() throws -> FileSystemScanBatch? {
    try Task.checkCancellation()
    if isFinished, issueBuffer.isEmpty {
      return nil
    }

    if enumerator == nil, !isFinished {
      try startEnumeration()
    }

    var records: [Record] = []
    records.reserveCapacity(batchSize)

    while records.count < batchSize {
      try Task.checkCancellation()

      if let issue = issueBuffer.popFirst() {
        issueCount += 1
        currentArea = issue.location.deletingLastPathComponent()
        records.append(.issue(issue))
        continue
      }

      guard !isFinished else {
        break
      }
      guard let url = enumerator?.nextObject() as? URL else {
        isFinished = true
        enumerator = nil
        continue
      }

      currentArea = url.deletingLastPathComponent()
      do {
        let item = try metadata(for: url)
        discoveredItemCount += 1
        records.append(.item(item))
      } catch {
        issueCount += 1
        records.append(.issue(Self.issue(for: url, error: error)))
      }
    }

    guard !records.isEmpty else {
      return nil
    }

    return FileSystemScanBatch(
      items: records.compactMap { record in
        guard case .item(let item) = record else {
          return nil
        }
        return item
      },
      issues: records.compactMap { record in
        guard case .issue(let issue) = record else {
          return nil
        }
        return issue
      },
      progress: ScanProgress(
        discoveredItemCount: discoveredItemCount,
        issueCount: issueCount,
        currentArea: currentArea
      )
    )
  }

  private func startEnumeration() throws {
    let issueBuffer = issueBuffer
    guard
      let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: Self.resourceKeys,
        options: [],
        errorHandler: { url, error in
          issueBuffer.append(Self.issue(for: url, error: error))
          return true
        }
      )
    else {
      throw FoundationScannerError.scopeUnavailable
    }
    self.enumerator = enumerator
  }

  private func metadata(for url: URL) throws -> ScannedItem {
    let values = try url.resourceValues(forKeys: Set(Self.resourceKeys))
    let kind: StorageItemKind
    if values.isSymbolicLink == true {
      kind = .symbolicLink
      enumerator?.skipDescendants()
    } else if values.isDirectory == true {
      kind = .folder
    } else if values.isRegularFile == true {
      kind = .file
    } else {
      kind = .other
    }

    return ScannedItem(
      id: UUID(),
      parentPath: url.deletingLastPathComponent().path(percentEncoded: false),
      location: url,
      name: values.name ?? url.lastPathComponent,
      kind: kind,
      diskUsedBytes: Self.int64(
        values.totalFileAllocatedSize ?? values.fileAllocatedSize
      ),
      apparentSizeBytes: Self.int64(
        values.totalFileSize ?? values.fileSize
      ),
      isHidden: values.isHidden ?? url.lastPathComponent.hasPrefix(".")
    )
  }

  private static var resourceKeys: [URLResourceKey] {
    [
      .nameKey,
      .isDirectoryKey,
      .isRegularFileKey,
      .isSymbolicLinkKey,
      .fileAllocatedSizeKey,
      .totalFileAllocatedSizeKey,
      .fileSizeKey,
      .totalFileSizeKey,
      .isHiddenKey,
    ]
  }

  private static func int64(_ value: Int?) -> Int64? {
    value.flatMap(Int64.init(exactly:))
  }

  fileprivate static func issue(for url: URL, error: any Error) -> ScanIssue {
    let cocoaError = error as? CocoaError
    let kind: ScanIssue.Kind =
      cocoaError?.code == .fileReadNoPermission
      ? .accessDenied
      : .metadataUnavailable
    let message =
      kind == .accessDenied
      ? "The item could not be accessed."
      : "The item metadata could not be read."
    return ScanIssue(
      location: url,
      kind: kind,
      message: message
    )
  }
}

private final class ScanIssueBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var issues: [ScanIssue] = []

  var isEmpty: Bool {
    lock.withLock {
      issues.isEmpty
    }
  }

  func append(_ issue: ScanIssue) {
    lock.withLock {
      issues.append(issue)
    }
  }

  func popFirst() -> ScanIssue? {
    lock.withLock {
      guard !issues.isEmpty else {
        return nil
      }
      return issues.removeFirst()
    }
  }
}
