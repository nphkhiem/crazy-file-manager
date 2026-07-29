import Foundation
import Testing

@testable import CrazyFileManager

@Suite("SQLite Scan Snapshot Index")
struct SQLiteScanSnapshotIndexTests {
  @Test
  func givenCandidateWithDifferentDiskUsage_whenLargestItemsAreQueried_thenReturnsDescendingOrder()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(for: .homeFolder(fixture.scopeURL))
    try await fixture.index.append(
      FileSystemScanBatch(
        items: [
          fixture.item(name: "small.bin", diskUsedBytes: 4_096),
          fixture.item(name: "large.bin", diskUsedBytes: 16_384),
        ],
        issues: [],
        progress: ScanProgress(
          discoveredItemCount: 2,
          issueCount: 0,
          currentArea: fixture.scopeURL
        )
      ),
      to: candidate
    )

    let results = try await fixture.index.largestItems(in: candidate, limit: 10)

    #expect(results.map(\.name) == ["large.bin", "small.bin"])
  }

  @Test
  func givenCandidateCountDoesNotMatch_whenCandidateIsPromoted_thenPromotionFails() async throws {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(for: .homeFolder(fixture.scopeURL))

    await #expect(throws: SnapshotIndexError.self) {
      try await fixture.index.promoteCandidate(
        candidate,
        expectedItemCount: 1,
        expectedIssueCount: 0
      )
    }
  }

  @Test
  func givenPersistedIssueCountDoesNotMatch_whenCandidateIsPromoted_thenPromotionFails()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(for: .homeFolder(fixture.scopeURL))
    try await fixture.index.append(
      FileSystemScanBatch(
        items: [],
        issues: [
          ScanIssue(
            location: fixture.scopeURL.appending(path: "restricted"),
            kind: .accessDenied,
            message: "The item could not be accessed."
          )
        ],
        progress: ScanProgress(
          discoveredItemCount: 0,
          issueCount: 1,
          currentArea: fixture.scopeURL
        )
      ),
      to: candidate
    )

    await #expect(
      throws: SnapshotIndexError.issueCountMismatch(
        expected: 0,
        actual: 1
      )
    ) {
      try await fixture.index.promoteCandidate(
        candidate,
        expectedItemCount: 0,
        expectedIssueCount: 0
      )
    }
  }

  @Test
  func givenCandidateWithPersistedItems_whenCandidateIsDiscarded_thenItemsAreUnavailable()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(for: .homeFolder(fixture.scopeURL))
    try await fixture.index.append(
      FileSystemScanBatch(
        items: [
          fixture.item(name: "temporary.bin", diskUsedBytes: 8_192)
        ],
        issues: [],
        progress: ScanProgress(
          discoveredItemCount: 1,
          issueCount: 0,
          currentArea: fixture.scopeURL
        )
      ),
      to: candidate
    )

    try await fixture.index.discardCandidate(candidate)

    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await fixture.index.largestItems(in: candidate, limit: 10)
    }
  }
}

private struct TemporarySnapshotIndexFixture {
  let directoryURL: URL
  let databaseURL: URL
  let scopeURL: URL
  let index: SQLiteScanSnapshotIndex

  init() throws {
    directoryURL = FileManager.default.temporaryDirectory
      .appending(path: "CrazyFileManagerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    databaseURL = directoryURL.appending(path: "snapshot.sqlite", directoryHint: .notDirectory)
    scopeURL = directoryURL.appending(path: "scope", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: scopeURL,
      withIntermediateDirectories: true
    )
    index = SQLiteScanSnapshotIndex(databaseURL: databaseURL)
  }

  func item(name: String, diskUsedBytes: Int64?) -> ScannedItem {
    let location = scopeURL.appending(path: name, directoryHint: .notDirectory)
    return ScannedItem(
      id: UUID(),
      parentPath: scopeURL.path(percentEncoded: false),
      location: location,
      name: name,
      kind: .file,
      diskUsedBytes: diskUsedBytes,
      apparentSizeBytes: diskUsedBytes,
      isHidden: false
    )
  }

  func remove() throws {
    try FileManager.default.removeItem(at: directoryURL)
  }
}
