import Foundation
import Testing

@testable import CrazyFileManager

@Suite("SQLite Scan Snapshot Index")
struct SQLiteScanSnapshotIndexTests {
  @Test
  func givenNestedSnapshot_whenCandidateIsPromoted_thenFolderTotalsAggregateBottomUp()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    try await fixture.index.append(
      fixture.batch(
        items: [
          fixture.folder(path: "Documents"),
          fixture.folder(path: "Documents/Archive"),
          fixture.file(
            path: "Documents/report.pdf",
            diskUsedBytes: 40,
            apparentSizeBytes: 50
          ),
          fixture.file(
            path: "Documents/Archive/data.bin",
            diskUsedBytes: 60,
            apparentSizeBytes: 70
          ),
          fixture.file(
            path: "root.bin",
            diskUsedBytes: 25,
            apparentSizeBytes: 30
          ),
        ]
      ),
      to: candidate
    )

    try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 5,
      expectedIssueCount: 0
    )
    let root = try await fixture.index.treeRoot(in: candidate)
    let rootPage = try await fixture.index.directChildren(
      of: root.id,
      in: candidate,
      offset: 0,
      limit: 20
    )
    let documentsRow = try #require(
      rootPage.items.first { $0.name == "Documents" }
    )
    let documentsPage = try await fixture.index.directChildren(
      of: documentsRow.id,
      in: candidate,
      offset: 0,
      limit: 20
    )
    let archiveRow = try #require(
      documentsPage.items.first { $0.name == "Archive" }
    )

    #expect(root.diskUsedBytes == 125)
    #expect(root.apparentSizeBytes == 150)
    #expect(documentsRow.diskUsedBytes == 100)
    #expect(archiveRow.diskUsedBytes == 60)
    #expect(documentsRow.parentID == root.id)
    #expect(archiveRow.parentID == documentsRow.id)
  }

  @Test
  func givenParentsWithIndependentChildren_whenPagesAreQueried_thenEachParentSortsAndPagesAlone()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    try await fixture.index.append(
      fixture.batch(
        items: [
          fixture.folder(path: "A"),
          fixture.folder(path: "B"),
          fixture.file(path: "A/small.bin", diskUsedBytes: 10),
          fixture.file(path: "A/large.bin", diskUsedBytes: 30),
          fixture.file(path: "A/middle.bin", diskUsedBytes: 20),
          fixture.file(path: "B/other.bin", diskUsedBytes: 100),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 6)
    let root = try await fixture.index.treeRoot(in: candidate)
    let rootPage = try await fixture.index.directChildren(
      of: root.id,
      in: candidate,
      offset: 0,
      limit: 20
    )
    let folderA = try #require(
      rootPage.items.first { $0.name == "A" }
    )

    let firstPage = try await fixture.index.directChildren(
      of: folderA.id,
      in: candidate,
      offset: 0,
      limit: 2
    )
    let secondPage = try await fixture.index.directChildren(
      of: folderA.id,
      in: candidate,
      offset: 2,
      limit: 2
    )

    #expect(firstPage.items.map(\.name) == ["large.bin", "middle.bin"])
    #expect(firstPage.nextOffset == 2)
    #expect(secondPage.items.map(\.name) == ["small.bin"])
    #expect(secondPage.nextOffset == nil)
  }

  @Test
  func givenUnknownLeafIssueAndEmptyFolder_whenTotalsAreQueried_thenValuesRemainHonest()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    try await fixture.index.append(
      fixture.batch(
        items: [
          fixture.folder(path: "Partial"),
          fixture.folder(path: "Empty"),
          fixture.file(
            path: "Partial/known.bin",
            diskUsedBytes: 40
          ),
          fixture.file(
            path: "Partial/unknown.bin",
            diskUsedBytes: nil
          ),
        ],
        issues: [
          fixture.issue(path: "Partial/restricted")
        ]
      ),
      to: candidate
    )
    try await fixture.promote(
      candidate,
      itemCount: 4,
      issueCount: 1
    )
    let root = try await fixture.index.treeRoot(in: candidate)
    let page = try await fixture.index.directChildren(
      of: root.id,
      in: candidate,
      offset: 0,
      limit: 20
    )
    let partial = try #require(
      page.items.first { $0.name == "Partial" }
    )
    let empty = try #require(
      page.items.first { $0.name == "Empty" }
    )

    #expect(partial.diskUsedBytes == 40)
    #expect(partial.isDiskUsedIncomplete)
    #expect(empty.diskUsedBytes == nil)
    #expect(!empty.isDiskUsedIncomplete)
    #expect(!empty.hasChildren)
    #expect(root.isRoot)
    #expect(root.parentID == nil)
  }

  @Test
  func givenItemWhoseParentWasNotIndexed_whenCandidateIsPromoted_thenPromotionFailsClosed()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    try await fixture.index.append(
      fixture.batch(
        items: [
          fixture.file(
            path: "missing/child.bin",
            diskUsedBytes: 40
          )
        ]
      ),
      to: candidate
    )

    await #expect(
      throws: SnapshotIndexError.orphanedItemCount(actual: 1)
    ) {
      try await fixture.promote(candidate, itemCount: 1)
    }
  }

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
    file(
      path: name,
      diskUsedBytes: diskUsedBytes,
      apparentSizeBytes: diskUsedBytes
    )
  }

  func folder(path: String) -> ScannedItem {
    let location = scopeURL.appending(
      path: path,
      directoryHint: .isDirectory
    )
    return ScannedItem(
      id: UUID(),
      parentPath: location.deletingLastPathComponent()
        .path(percentEncoded: false),
      location: location,
      name: location.lastPathComponent,
      kind: .folder,
      diskUsedBytes: nil,
      apparentSizeBytes: nil,
      isHidden: false
    )
  }

  func file(
    path: String,
    diskUsedBytes: Int64?,
    apparentSizeBytes: Int64?
  ) -> ScannedItem {
    let location = scopeURL.appending(
      path: path,
      directoryHint: .notDirectory
    )
    return ScannedItem(
      id: UUID(),
      parentPath: location.deletingLastPathComponent()
        .path(percentEncoded: false),
      location: location,
      name: location.lastPathComponent,
      kind: .file,
      diskUsedBytes: diskUsedBytes,
      apparentSizeBytes: apparentSizeBytes,
      isHidden: false
    )
  }

  func file(
    path: String,
    diskUsedBytes: Int64?
  ) -> ScannedItem {
    file(
      path: path,
      diskUsedBytes: diskUsedBytes,
      apparentSizeBytes: diskUsedBytes
    )
  }

  func batch(
    items: [ScannedItem],
    issues: [ScanIssue] = []
  ) -> FileSystemScanBatch {
    FileSystemScanBatch(
      items: items,
      issues: issues,
      progress: ScanProgress(
        discoveredItemCount: items.count,
        issueCount: issues.count,
        currentArea: scopeURL
      )
    )
  }

  func issue(path: String) -> ScanIssue {
    ScanIssue(
      location: scopeURL.appending(path: path),
      kind: .accessDenied,
      message: "The item could not be accessed."
    )
  }

  func promote(
    _ candidate: ScanID,
    itemCount: Int,
    issueCount: Int = 0
  ) async throws {
    try await index.promoteCandidate(
      candidate,
      expectedItemCount: itemCount,
      expectedIssueCount: issueCount
    )
  }

  func remove() throws {
    try FileManager.default.removeItem(at: directoryURL)
  }
}
