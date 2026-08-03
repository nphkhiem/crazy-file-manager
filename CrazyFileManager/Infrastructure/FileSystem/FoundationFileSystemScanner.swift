import Foundation

protocol CloudMetadataReading: Sendable {
  func isCloudOnly(at url: URL) throws -> Bool
}

protocol VolumeMetadataReading: Sendable {
  func volumeIdentity(at location: URL) throws -> ScanVolumeIdentity?
}

protocol FileIdentityReading: Sendable {
  func fileResourceIdentifier(at url: URL) throws -> AnyHashable?
}

struct FoundationFileSystemScanner: FileSystemScanning {
  private let batchSize: Int
  private let cloudMetadataReader: (any CloudMetadataReading)?
  private let volumeMetadataReader: (any VolumeMetadataReading)?
  private let fileIdentityReader: (any FileIdentityReading)?

  init(
    batchSize: Int = 128,
    cloudMetadataReader: (any CloudMetadataReading)? = nil,
    fileIdentityReader: (any FileIdentityReading)? = nil,
    volumeMetadataReader: (any VolumeMetadataReading)? = nil
  ) {
    self.batchSize = max(1, batchSize)
    self.cloudMetadataReader = cloudMetadataReader
    self.fileIdentityReader = fileIdentityReader
    self.volumeMetadataReader = volumeMetadataReader
  }

  func batches(
    for scope: ScanScope
  ) async -> AsyncThrowingStream<FileSystemScanBatch, Error> {
    let cursor = FoundationScanCursor(
      rootURL: scope.location,
      expectedVolumeIdentity: scope.volumeIdentity,
      batchSize: batchSize,
      cloudMetadataReader: cloudMetadataReader,
      fileIdentityReader: fileIdentityReader,
      volumeMetadataReader: volumeMetadataReader
    )
    return AsyncThrowingStream {
      try Task.checkCancellation()
      return try await cursor.nextBatch()
    }
  }
}

enum FileSystemScanError: Error, Equatable {
  case scopeUnavailable
  case scopeChanged
}

private actor FoundationScanCursor {
  private enum VolumeBoundaryError: Error {
    case unavailable
  }

  private enum ConsistencyAnomalyError: Error {
    case ambiguousIdentity
  }

  private enum Record {
    case item(ScannedItem)
    case issue(ScanIssue)
  }

  private let rootURL: URL
  private let expectedVolumeIdentity: ScanVolumeIdentity
  private let canonicalRootPath: String
  private let batchSize: Int
  private let cloudMetadataReader: (any CloudMetadataReading)?
  private let fileIdentityReader: (any FileIdentityReading)?
  private let volumeMetadataReader: (any VolumeMetadataReading)?
  private let issueBuffer = ScanIssueBuffer()
  private var enumerator: FileManager.DirectoryEnumerator?
  private var discoveredItemCount = 0
  private var issueCount = 0
  private var currentArea: URL?
  private var isFinished = false
  private var identityIDs: [AnyHashable: UUID] = [:]

  init(
    rootURL: URL,
    expectedVolumeIdentity: ScanVolumeIdentity,
    batchSize: Int,
    cloudMetadataReader: (any CloudMetadataReading)?,
    fileIdentityReader: (any FileIdentityReading)?,
    volumeMetadataReader: (any VolumeMetadataReading)?
  ) {
    self.rootURL = rootURL
    self.expectedVolumeIdentity = expectedVolumeIdentity
    canonicalRootPath =
      (try? rootURL.resourceValues(forKeys: [.canonicalPathKey]))?
      .canonicalPath ?? rootURL.path(percentEncoded: false)
    self.batchSize = batchSize
    self.cloudMetadataReader = cloudMetadataReader
    self.fileIdentityReader = fileIdentityReader
    self.volumeMetadataReader = volumeMetadataReader
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

      let normalizedURL = normalizedURL(url)
      currentArea = normalizedURL.deletingLastPathComponent()
      do {
        let item = try metadata(for: url, normalizedURL: normalizedURL)
        discoveredItemCount += 1
        records.append(.item(item))
      } catch is VolumeBoundaryError {
        issueCount += 1
        records.append(.issue(Self.volumeIssue(for: normalizedURL)))
      } catch is ConsistencyAnomalyError {
        issueCount += 1
        records.append(.issue(Self.consistencyIssue(for: normalizedURL)))
      } catch {
        issueCount += 1
        records.append(.issue(Self.issue(for: normalizedURL, error: error)))
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
    if expectedVolumeIdentity.isVerified {
      guard
        let currentVolumeIdentity = try volumeIdentity(at: rootURL)
      else {
        throw FileSystemScanError.scopeUnavailable
      }
      guard currentVolumeIdentity == expectedVolumeIdentity else {
        throw FileSystemScanError.scopeChanged
      }
    }
    let issueBuffer = issueBuffer
    let rootURL = rootURL
    let canonicalRootPath = canonicalRootPath
    guard
      let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: Self.resourceKeys,
        options: [],
        errorHandler: { url, error in
          let normalizedURL = Self.normalizedURL(
            url,
            rootURL: rootURL,
            canonicalRootPath: canonicalRootPath
          )
          issueBuffer.append(Self.issue(for: normalizedURL, error: error))
          return true
        }
      )
    else {
      throw FileSystemScanError.scopeUnavailable
    }
    self.enumerator = enumerator
  }

  private func metadata(
    for url: URL,
    normalizedURL: URL
  ) throws -> ScannedItem {
    let values = try url.resourceValues(forKeys: Set(Self.resourceKeys))
    if expectedVolumeIdentity.isVerified {
      guard
        try volumeIdentity(at: url, values: values)
          == expectedVolumeIdentity
      else {
        if values.isDirectory == true {
          enumerator?.skipDescendants()
        }
        throw VolumeBoundaryError.unavailable
      }
    }
    let resolvedResourceIdentifier: AnyHashable? =
      try fileIdentityReader?.fileResourceIdentifier(at: url)
      ?? (values.fileResourceIdentifier as? AnyHashable)
    if let resolvedResourceIdentifier, identityIDs[resolvedResourceIdentifier] != nil {
      guard let linkCount = values.linkCount, linkCount > 1 else {
        throw ConsistencyAnomalyError.ambiguousIdentity
      }
    }
    let kind: StorageItemKind
    if values.isSymbolicLink == true {
      kind = .symbolicLink
      enumerator?.skipDescendants()
    } else if values.isPackage == true {
      kind = .package
    } else if values.isDirectory == true {
      kind = .folder
    } else if values.isRegularFile == true {
      kind = .file
    } else {
      kind = .other
    }

    return ScannedItem(
      id: UUID(),
      parentPath: normalizedURL.deletingLastPathComponent()
        .path(percentEncoded: false),
      location: normalizedURL,
      name: values.name ?? url.lastPathComponent,
      kind: kind,
      diskUsedBytes: Self.int64(
        values.totalFileAllocatedSize ?? values.fileAllocatedSize
      ),
      apparentSizeBytes: Self.int64(
        values.totalFileSize ?? values.fileSize
      ),
      isHidden: values.isHidden ?? url.lastPathComponent.hasPrefix("."),
      isCloudOnly: try cloudMetadataReader?.isCloudOnly(at: url)
        ?? Self.isCloudOnly(values),
      fileSystemIdentity: identity(for: resolvedResourceIdentifier),
      hardLinkCount: values.linkCount
    )
  }

  private func identity(for resourceIdentifier: AnyHashable?) -> UUID? {
    guard let resourceIdentifier else {
      return nil
    }
    if let identity = identityIDs[resourceIdentifier] {
      return identity
    }
    let identity = UUID()
    identityIDs[resourceIdentifier] = identity
    return identity
  }

  private static var resourceKeys: [URLResourceKey] {
    [
      .nameKey,
      .isDirectoryKey,
      .isRegularFileKey,
      .isSymbolicLinkKey,
      .isPackageKey,
      .fileAllocatedSizeKey,
      .totalFileAllocatedSizeKey,
      .fileSizeKey,
      .totalFileSizeKey,
      .isHiddenKey,
      .fileResourceIdentifierKey,
      .linkCountKey,
      .volumeUUIDStringKey,
      .isUbiquitousItemKey,
      .ubiquitousItemDownloadingStatusKey,
    ]
  }

  private static func isCloudOnly(_ values: URLResourceValues) -> Bool {
    values.isUbiquitousItem == true
      && values.ubiquitousItemDownloadingStatus == .notDownloaded
  }

  private static func int64(_ value: Int?) -> Int64? {
    value.flatMap(Int64.init(exactly:))
  }

  private func normalizedURL(_ url: URL) -> URL {
    Self.normalizedURL(
      url,
      rootURL: rootURL,
      canonicalRootPath: canonicalRootPath
    )
  }

  private func volumeIdentity(
    at url: URL,
    values: URLResourceValues? = nil
  ) throws -> ScanVolumeIdentity? {
    if let volumeMetadataReader {
      return try volumeMetadataReader.volumeIdentity(at: url)
    }
    let rawValue =
      try values?.volumeUUIDString
      ?? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    return rawValue.map(ScanVolumeIdentity.init(rawValue:))
  }

  private static func normalizedURL(
    _ url: URL,
    rootURL: URL,
    canonicalRootPath: String
  ) -> URL {
    let path = url.path(percentEncoded: false)
    let prefix =
      canonicalRootPath.hasSuffix("/")
      ? canonicalRootPath
      : canonicalRootPath + "/"
    guard path.hasPrefix(prefix) else {
      return url
    }
    let relativePath = String(path.dropFirst(prefix.count))
    return rootURL.appending(
      path: relativePath,
      directoryHint: url.hasDirectoryPath ? .isDirectory : .notDirectory
    )
  }

  fileprivate static func issue(for url: URL, error: any Error) -> ScanIssue {
    let cocoaError = error as? CocoaError
    let kind: ScanIssue.Kind
    let message: String
    switch cocoaError?.code {
    case .fileReadNoPermission:
      kind = .accessDenied
      message = "The item could not be accessed."
    case .fileNoSuchFile:
      kind = .changed
      message = "This item changed while it was being scanned."
    default:
      kind = .metadataUnavailable
      message = "The item metadata could not be read."
    }
    return ScanIssue(
      location: url,
      kind: kind,
      message: message
    )
  }

  private static func consistencyIssue(for url: URL) -> ScanIssue {
    ScanIssue(
      location: url,
      kind: .consistency,
      message: "This item’s filesystem identity could not be confirmed."
    )
  }

  private static func volumeIssue(for url: URL) -> ScanIssue {
    ScanIssue(
      location: url,
      kind: .volumeUnavailable,
      message: "The item is on a different or unavailable volume."
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
