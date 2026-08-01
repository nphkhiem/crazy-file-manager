import Foundation
import SQLite3
import Testing

@testable import CrazyFileManager

@Suite("SQLite Scan Snapshot Index")
struct SQLiteScanSnapshotIndexTests {
  @Test
  func givenCandidate_whenPromotionCompletes_thenSnapshotUsesCompletionDerivedExpiry()
    async throws
  {
    let startedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T09:30:00Z")
    )
    let completionDate = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let dateProvider = MutableDateProvider(now: startedAt)
    let fixture = try TemporarySnapshotIndexFixture(
      dateProvider: dateProvider
    )
    defer { try? fixture.remove() }
    let scope = ScanScope(
      kind: .custom,
      location: fixture.scopeURL,
      volumeIdentity: ScanVolumeIdentity(rawValue: "volume-identity"),
      volumeCharacteristics: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    let candidate = try await fixture.index.beginCandidate(for: scope)
    try await fixture.index.append(
      fixture.batch(items: [fixture.item(name: "report.pdf", diskUsedBytes: 1)]),
      to: candidate
    )
    dateProvider.advance(to: completionDate)

    let snapshot = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 1,
      expectedIssueCount: 0
    )

    #expect(snapshot.completedAt == completionDate)
    #expect(snapshot.expiresAt == completionDate.addingTimeInterval(86_400))
    #expect(snapshot.scope == scope)
    #expect(
      snapshot.completion
        == ScanCompletion(
          accessibleItemCount: 1,
          issueCount: 0
        )
    )
  }

  @Test
  func givenTwoPromotions_whenSecondCompletes_thenOnlySecondSnapshotRemains()
    async throws
  {
    let firstCompletion = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let secondCompletion = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T11:00:00Z")
    )
    let dateProvider = MutableDateProvider(now: firstCompletion)
    let fixture = try TemporarySnapshotIndexFixture(
      dateProvider: dateProvider
    )
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let first = try await fixture.index.beginCandidate(for: scope)
    let firstSnapshot = try await fixture.index.promoteCandidate(
      first,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )
    dateProvider.advance(to: secondCompletion)
    let second = try await fixture.index.beginCandidate(for: scope)

    let secondSnapshot = try await fixture.index.promoteCandidate(
      second,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )

    #expect(firstSnapshot.scanID == first)
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await fixture.index.treeRoot(in: first)
    }
    #expect(secondSnapshot.scanID == second)
    #expect(secondSnapshot.completedAt == secondCompletion)
    #expect(secondSnapshot.expiresAt == secondCompletion.addingTimeInterval(86_400))
  }

  @Test
  func givenPackageDescendants_whenCandidateIsPromoted_thenPackageAggregatesButRemainsLeaf()
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
          fixture.package(path: "Sample.app"),
          fixture.folder(path: "Sample.app/Contents"),
          fixture.file(
            path: "Sample.app/Contents/payload.bin",
            diskUsedBytes: 50,
            isCloudOnly: true,
            fileSystemIdentity: UUID(),
            hardLinkCount: 2
          ),
        ],
        issues: [fixture.issue(path: "Sample.app/Contents/restricted")]
      ),
      to: candidate
    )

    let liveLargestItems = try await fixture.index.largestItems(
      in: candidate,
      limit: 10
    )
    #expect(liveLargestItems.map(\.name) == ["Sample.app"])
    #expect(liveLargestItems.first?.diskUsedBytes == 50)
    #expect(liveLargestItems.first?.isShared == true)
    #expect(liveLargestItems.first?.isCloudOnly == true)

    let snapshot = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 3,
      expectedIssueCount: 1
    )
    let package = try #require(
      snapshot.rootPage.items.first { $0.name == "Sample.app" }
    )

    #expect(package.kind == .package)
    #expect(package.diskUsedBytes == 50)
    #expect(package.isDiskUsedIncomplete)
    #expect(package.isShared)
    #expect(package.isCloudOnly)
    #expect(!package.hasChildren)
    #expect(snapshot.largestItems.map(\.name) == ["Sample.app"])
    await #expect(throws: SnapshotIndexError.integrityCheckFailed) {
      try await fixture.index.directChildren(
        of: package.id,
        in: candidate,
        offset: 0,
        limit: 20
      )
    }
  }

  @Test
  func givenPackageWithUnknownCloudDescendant_whenLiveItemsQueried_thenSizeRemainsUnknown()
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
          fixture.package(path: "Cloud.app", diskUsedBytes: 4_096),
          fixture.file(
            path: "Cloud.app/payload.bin",
            diskUsedBytes: nil,
            isCloudOnly: true
          ),
        ]
      ),
      to: candidate
    )

    let package = try #require(
      try await fixture.index.largestItems(
        in: candidate,
        limit: 10
      ).first
    )

    #expect(package.name == "Cloud.app")
    #expect(package.diskUsedBytes == nil)
    #expect(package.isCloudOnly)
  }

  @Test
  func givenKnownHardLinks_whenCandidateIsPromoted_thenBytesCountOnceAndRowsAreShared()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let identity = UUID()
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    try await fixture.index.append(
      fixture.batch(
        items: [
          fixture.folder(path: "A"),
          fixture.folder(path: "B"),
          fixture.file(
            path: "A/original.bin",
            diskUsedBytes: 40,
            fileSystemIdentity: identity,
            hardLinkCount: 2
          ),
          fixture.file(
            path: "B/linked.bin",
            diskUsedBytes: 40,
            fileSystemIdentity: identity,
            hardLinkCount: 2
          ),
        ]
      ),
      to: candidate
    )

    let liveLinkedSummaries = try await fixture.index.largestItems(
      in: candidate,
      limit: 10
    ).filter {
      $0.name == "original.bin" || $0.name == "linked.bin"
    }
    #expect(liveLinkedSummaries.count == 2)
    #expect(liveLinkedSummaries.allSatisfy { $0.isShared })

    let snapshot = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 4,
      expectedIssueCount: 0
    )
    let folderA = try #require(
      snapshot.rootPage.items.first { $0.name == "A" }
    )
    let original = try #require(
      try await fixture.index.directChildren(
        of: folderA.id,
        in: candidate,
        offset: 0,
        limit: 20
      ).items.first
    )
    let linkedSummaries = snapshot.largestItems.filter {
      $0.name == "original.bin" || $0.name == "linked.bin"
    }

    #expect(snapshot.treeRoot.diskUsedBytes == 40)
    #expect(snapshot.treeRoot.isShared)
    #expect(snapshot.rootPage.items.allSatisfy { $0.isShared })
    #expect(original.diskUsedBytes == 40)
    #expect(original.isShared)
    #expect(linkedSummaries.count == 2)
    #expect(linkedSummaries.allSatisfy { $0.isShared })
  }

  @Test
  func givenDirectoryLinkCount_whenPromoted_thenFolderIsNotSharedWithoutSharedDescendant()
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
          fixture.folder(
            path: "Ordinary",
            fileSystemIdentity: UUID(),
            hardLinkCount: 4
          )
        ]
      ),
      to: candidate
    )

    let snapshot = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 1,
      expectedIssueCount: 0
    )
    let folder = try #require(snapshot.rootPage.items.first)

    #expect(!folder.isShared)
    #expect(!snapshot.treeRoot.isShared)
  }

  @Test
  func givenHiddenCloudAndIssue_whenPromoted_thenStatusesAndNullabilityPropagate()
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
          fixture.file(
            path: "Partial/.hidden.bin",
            diskUsedBytes: 5,
            isHidden: true
          ),
          fixture.file(
            path: "Partial/cloud.bin",
            diskUsedBytes: nil,
            isCloudOnly: true
          ),
        ],
        issues: [fixture.issue(path: "Partial/restricted")]
      ),
      to: candidate
    )

    let snapshot = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 3,
      expectedIssueCount: 1
    )
    let partial = try #require(
      snapshot.rootPage.items.first { $0.name == "Partial" }
    )
    let children = try await fixture.index.directChildren(
      of: partial.id,
      in: candidate,
      offset: 0,
      limit: 20
    ).items
    let hidden = try #require(children.first { $0.name == ".hidden.bin" })
    let cloud = try #require(children.first { $0.name == "cloud.bin" })
    let summaries = snapshot.largestItems

    #expect(hidden.isHidden)
    #expect(cloud.isCloudOnly)
    #expect(cloud.diskUsedBytes == nil)
    #expect(partial.isCloudOnly)
    #expect(partial.isDiskUsedIncomplete)
    #expect(snapshot.treeRoot.isCloudOnly)
    #expect(snapshot.treeRoot.isDiskUsedIncomplete)
    #expect(summaries.first { $0.name == ".hidden.bin" }?.isHidden == true)
    #expect(summaries.first { $0.name == "cloud.bin" }?.isCloudOnly == true)
    #expect(summaries.first { $0.name == "cloud.bin" }?.diskUsedBytes == nil)
  }

  @Test
  func givenVersionTwoCompletedSnapshotWithoutStableScope_whenIndexOpens_thenSnapshotIsDeleted()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let completed = try fixture.seedVersionTwoSnapshot()
    let relaunchedIndex = SQLiteScanSnapshotIndex(
      databaseURL: fixture.databaseURL
    )

    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await relaunchedIndex.treeRoot(in: completed)
    }
    #expect(try fixture.userVersion() == 4)
  }

  @Test
  func
    givenVersionThreeCandidateAndLegacyCompletedSnapshot_whenIndexOpens_thenBothSnapshotsAreDeleted()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let snapshots = try fixture.seedVersionThreeCandidateAndLegacyCompleted()
    let relaunchedIndex = SQLiteScanSnapshotIndex(
      databaseURL: fixture.databaseURL
    )

    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await relaunchedIndex.treeRoot(in: snapshots.candidate)
    }
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await relaunchedIndex.treeRoot(in: snapshots.completed)
    }
    #expect(try fixture.userVersion() == 4)
  }

  @Test
  func givenVersionThreeDatabaseWithIncompatibleItemsView_whenIndexOpens_thenMigrationRollsBack()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    try fixture.seedVersionThreeDatabaseWithIncompatibleItemsView()
    let index = SQLiteScanSnapshotIndex(databaseURL: fixture.databaseURL)

    await #expect(throws: SnapshotIndexError.self) {
      try await index.removeCrashLeftoverCandidates()
    }

    let scanColumns = try fixture.scanColumnNames()
    #expect(try fixture.userVersion() == 3)
    #expect(!scanColumns.contains("scope_kind"))
    #expect(!scanColumns.contains("expires_at"))
  }

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

    let promotedSnapshot = try await fixture.index.promoteCandidate(
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
    #expect(promotedSnapshot.treeRoot == root)
    #expect(promotedSnapshot.rootPage == rootPage)
    #expect(
      promotedSnapshot.largestItems.map(\.name) == [
        "data.bin",
        "report.pdf",
        "root.bin",
        "Archive",
        "Documents",
      ]
    )
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
  func givenMissingApparentSize_whenCandidateIsPromoted_thenOnlyApparentTotalIsIncomplete()
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
          fixture.folder(path: "Independent"),
          fixture.file(
            path: "Independent/known.bin",
            diskUsedBytes: 10,
            apparentSizeBytes: 20
          ),
          fixture.file(
            path: "Independent/apparent-unknown.bin",
            diskUsedBytes: 30,
            apparentSizeBytes: nil
          ),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 3)
    let root = try await fixture.index.treeRoot(in: candidate)
    let page = try await fixture.index.directChildren(
      of: root.id,
      in: candidate,
      offset: 0,
      limit: 20
    )
    let independent = try #require(
      page.items.first { $0.name == "Independent" }
    )

    #expect(independent.diskUsedBytes == 40)
    #expect(!independent.isDiskUsedIncomplete)
    #expect(independent.apparentSizeBytes == 20)
    #expect(independent.isApparentSizeIncomplete)
  }

  @Test
  func givenRootScopeWithDescendantIssue_whenCandidateIsPromoted_thenRootIsIncomplete()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let rootURL = URL(fileURLWithPath: "/", isDirectory: true)
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(rootURL)
    )
    try await fixture.index.append(
      fixture.batch(
        items: [],
        issues: [
          ScanIssue(
            location: rootURL.appending(path: "restricted"),
            kind: .accessDenied,
            message: "The item could not be accessed."
          )
        ]
      ),
      to: candidate
    )

    try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 0,
      expectedIssueCount: 1
    )
    let root = try await fixture.index.treeRoot(in: candidate)

    #expect(root.diskUsedBytes == nil)
    #expect(root.apparentSizeBytes == nil)
    #expect(root.isDiskUsedIncomplete)
    #expect(root.isApparentSizeIncomplete)
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

  @Test
  func givenCompletedAndCrashLeftoverCandidate_whenLaunchCleanupRuns_thenOnlyCandidateIsRemoved()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let completed = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    try await fixture.promote(completed, itemCount: 0)
    let crashLeftover = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    let relaunchedIndex = SQLiteScanSnapshotIndex(
      databaseURL: fixture.databaseURL
    )

    try await relaunchedIndex.removeCrashLeftoverCandidates()

    #expect(try await relaunchedIndex.treeRoot(in: completed).isRoot)
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await relaunchedIndex.largestItems(
        in: crashLeftover,
        limit: 10
      )
    }
  }

  @Test
  func
    givenCompletedSnapshotBeforeExpiry_whenPreparingCacheForLaunch_thenBoundedSnapshotIsAvailable()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let dateProvider = MutableDateProvider(
      now: completedAt.addingTimeInterval(-1)
    )
    let fixture = try TemporarySnapshotIndexFixture(
      dateProvider: dateProvider
    )
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let candidate = try await fixture.index.beginCandidate(for: scope)
    try await fixture.index.append(
      fixture.batch(items: [fixture.item(name: "report.pdf", diskUsedBytes: 12)]),
      to: candidate
    )
    dateProvider.advance(to: completedAt)
    let promoted = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 1,
      expectedIssueCount: 0,
      largestItemLimit: 1,
      treePageLimit: 1
    )
    dateProvider.advance(to: promoted.expiresAt.addingTimeInterval(-0.001))

    let preparation = try await fixture.index.prepareCacheForLaunch(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    guard case .available(let snapshot) = preparation else {
      Issue.record("Expected a valid cached snapshot.")
      return
    }
    #expect(snapshot.scanID == promoted.scanID)
    #expect(snapshot.scope == scope)
    #expect(snapshot.completedAt == promoted.completedAt)
    #expect(snapshot.expiresAt == promoted.expiresAt)
    #expect(snapshot.completion == promoted.completion)
    #expect(snapshot.largestItems == promoted.largestItems)
    #expect(snapshot.treeRoot == promoted.treeRoot)
    #expect(snapshot.rootPage == promoted.rootPage)
  }

  @Test
  func givenCompletedSnapshotAtExpiry_whenPreparingCacheForLaunch_thenSnapshotIsExpiredAndDeleted()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let dateProvider = MutableDateProvider(now: completedAt)
    let fixture = try TemporarySnapshotIndexFixture(
      dateProvider: dateProvider
    )
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let candidate = try await fixture.index.beginCandidate(for: scope)
    let promoted = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )
    dateProvider.advance(to: promoted.expiresAt)

    let preparation = try await fixture.index.prepareCacheForLaunch(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    #expect(
      preparation
        == .expired(
          previousScope: scope,
          completedAt: completedAt
        )
    )
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await fixture.index.treeRoot(in: promoted.scanID)
    }
    #expect(
      try await fixture.index.prepareCacheForLaunch(
        largestItemLimit: 1,
        treePageLimit: 1
      ) == .empty
    )
  }

  @Test
  func givenClockBeforeCompletion_whenRefreshingCompletedCache_thenSnapshotIsExpiredAndDeleted()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let dateProvider = MutableDateProvider(now: completedAt)
    let fixture = try TemporarySnapshotIndexFixture(
      dateProvider: dateProvider
    )
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let candidate = try await fixture.index.beginCandidate(for: scope)
    let promoted = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )
    dateProvider.advance(to: completedAt.addingTimeInterval(-0.001))

    let preparation = try await fixture.index.refreshCompletedCache(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    #expect(
      preparation
        == .expired(
          previousScope: scope,
          completedAt: completedAt
        )
    )
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await fixture.index.treeRoot(in: promoted.scanID)
    }
  }

  @Test
  func givenClockAfterExpiry_whenRefreshingCompletedCache_thenSnapshotIsExpiredAndDeleted()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let dateProvider = MutableDateProvider(now: completedAt)
    let fixture = try TemporarySnapshotIndexFixture(
      dateProvider: dateProvider
    )
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let candidate = try await fixture.index.beginCandidate(for: scope)
    let promoted = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )
    dateProvider.advance(to: promoted.expiresAt.addingTimeInterval(0.001))

    let preparation = try await fixture.index.refreshCompletedCache(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    #expect(
      preparation
        == .expired(
          previousScope: scope,
          completedAt: completedAt
        )
    )
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await fixture.index.treeRoot(in: promoted.scanID)
    }
  }

  @Test
  func
    givenValidCompletedSnapshotAndCandidate_whenPreparingCacheForLaunch_thenCompletedSnapshotLoadsAndCandidateIsRemoved()
    async throws
  {
    let completionDate = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let dateProvider = MutableDateProvider(now: completionDate)
    let fixture = try TemporarySnapshotIndexFixture(
      dateProvider: dateProvider
    )
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let completedCandidate = try await fixture.index.beginCandidate(for: scope)
    let promoted = try await fixture.index.promoteCandidate(
      completedCandidate,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )
    let crashLeftover = try await fixture.index.beginCandidate(for: scope)

    let preparation = try await fixture.index.prepareCacheForLaunch(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    guard case .available(let snapshot) = preparation else {
      Issue.record("Expected a valid completed snapshot.")
      return
    }
    #expect(snapshot.scanID == promoted.scanID)
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await fixture.index.treeRoot(in: crashLeftover)
    }
  }

  @Test
  func
    givenCompletedSnapshotAndCandidate_whenClearingCompletedSnapshot_thenOnlyCompletedSnapshotIsRemoved()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let completedCandidate = try await fixture.index.beginCandidate(for: scope)
    let completed = try await fixture.index.promoteCandidate(
      completedCandidate,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )
    let candidate = try await fixture.index.beginCandidate(for: scope)

    try await fixture.index.clearCompletedSnapshot()

    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await fixture.index.treeRoot(in: completed.scanID)
    }
    #expect(try await fixture.index.treeRoot(in: candidate).isRoot)
  }

  @Test
  func
    givenExpiredSnapshotWithDeletionFailure_whenRefreshingCompletedCache_thenCleanupFailureDoesNotReturnStaleProjection()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let dateProvider = MutableDateProvider(now: completedAt)
    let fixture = try TemporarySnapshotIndexFixture(
      dateProvider: dateProvider
    )
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let candidate = try await fixture.index.beginCandidate(for: scope)
    let promoted = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )
    try fixture.installCompletedDeleteFailureTrigger()
    dateProvider.advance(to: promoted.expiresAt)

    let failedCleanup = try await fixture.index.refreshCompletedCache(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    #expect(
      failedCleanup
        == .cleanupFailed(
          previousScope: scope,
          completedAt: completedAt
        )
    )
    try fixture.removeCompletedDeleteFailureTrigger()
    #expect(
      try await fixture.index.refreshCompletedCache(
        largestItemLimit: 1,
        treePageLimit: 1
      )
        == .expired(
          previousScope: scope,
          completedAt: completedAt
        )
    )
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await fixture.index.treeRoot(in: promoted.scanID)
    }
  }

  @Test
  func givenIncompatibleSchema_whenPreparingCacheForLaunch_thenDatabaseIsReconstructed()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    try fixture.seedIncompatibleDatabase()

    let preparation = try await fixture.index.prepareCacheForLaunch(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    #expect(preparation == .reconstructed)
    #expect(try fixture.userVersion() == 4)
    #expect(
      try await fixture.index.prepareCacheForLaunch(
        largestItemLimit: 1,
        treePageLimit: 1
      ) == .empty
    )
    #expect(!FileManager.default.fileExists(atPath: "\(fixture.databaseURL.path)-wal"))
    #expect(!FileManager.default.fileExists(atPath: "\(fixture.databaseURL.path)-shm"))
  }

  @Test
  func givenCorruptDatabase_whenPreparingCacheForLaunch_thenDatabaseIsReconstructed()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    try fixture.writeCorruptDatabase()

    let preparation = try await fixture.index.prepareCacheForLaunch(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    #expect(preparation == .reconstructed)
    #expect(try fixture.userVersion() == 4)
    #expect(
      try await fixture.index.prepareCacheForLaunch(
        largestItemLimit: 1,
        treePageLimit: 1
      ) == .empty
    )
    #expect(!FileManager.default.fileExists(atPath: "\(fixture.databaseURL.path)-wal"))
    #expect(!FileManager.default.fileExists(atPath: "\(fixture.databaseURL.path)-shm"))
  }

  @Test
  func
    givenSchemaMetadataIsBusy_whenPreparingCacheForLaunch_thenBusyIsPropagatedAndDatabaseRemainsUntouched()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    let lock = try SQLiteExclusiveLock(databaseURL: fixture.databaseURL)
    defer { lock.release() }

    await #expect(throws: SnapshotIndexError.statementFailed(code: SQLITE_BUSY)) {
      try await fixture.index.prepareCacheForLaunch(
        largestItemLimit: 1,
        treePageLimit: 1
      )
    }

    lock.release()
    #expect(try fixture.userVersion() == 4)
    #expect(try await fixture.index.treeRoot(in: candidate).isRoot)
  }
}

private struct TemporarySnapshotIndexFixture {
  let directoryURL: URL
  let databaseURL: URL
  let scopeURL: URL
  let index: SQLiteScanSnapshotIndex

  init(dateProvider: any DateProviding = SystemDateProvider()) throws {
    directoryURL = FileManager.default.temporaryDirectory
      .appending(path: "CrazyFileManagerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    databaseURL = directoryURL.appending(path: "snapshot.sqlite", directoryHint: .notDirectory)
    scopeURL = directoryURL.appending(path: "scope", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: scopeURL,
      withIntermediateDirectories: true
    )
    index = SQLiteScanSnapshotIndex(
      databaseURL: databaseURL,
      dateProvider: dateProvider
    )
  }

  func item(name: String, diskUsedBytes: Int64?) -> ScannedItem {
    file(
      path: name,
      diskUsedBytes: diskUsedBytes,
      apparentSizeBytes: diskUsedBytes
    )
  }

  func folder(
    path: String,
    fileSystemIdentity: UUID? = nil,
    hardLinkCount: Int? = nil
  ) -> ScannedItem {
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
      isHidden: false,
      fileSystemIdentity: fileSystemIdentity,
      hardLinkCount: hardLinkCount
    )
  }

  func package(
    path: String,
    diskUsedBytes: Int64? = nil
  ) -> ScannedItem {
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
      kind: .package,
      diskUsedBytes: diskUsedBytes,
      apparentSizeBytes: nil,
      isHidden: false
    )
  }

  func file(
    path: String,
    diskUsedBytes: Int64?,
    apparentSizeBytes: Int64?,
    isHidden: Bool = false,
    isCloudOnly: Bool = false,
    fileSystemIdentity: UUID? = nil,
    hardLinkCount: Int? = nil
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
      isHidden: isHidden,
      isCloudOnly: isCloudOnly,
      fileSystemIdentity: fileSystemIdentity,
      hardLinkCount: hardLinkCount
    )
  }

  func file(
    path: String,
    diskUsedBytes: Int64?,
    isHidden: Bool = false,
    isCloudOnly: Bool = false,
    fileSystemIdentity: UUID? = nil,
    hardLinkCount: Int? = nil
  ) -> ScannedItem {
    file(
      path: path,
      diskUsedBytes: diskUsedBytes,
      apparentSizeBytes: diskUsedBytes,
      isHidden: isHidden,
      isCloudOnly: isCloudOnly,
      fileSystemIdentity: fileSystemIdentity,
      hardLinkCount: hardLinkCount
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

  func seedVersionTwoSnapshot() throws -> ScanID {
    let scan = ScanID(rawValue: UUID())
    let rootID = UUID()
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try SQLiteDatabase.execute(
        """
        CREATE TABLE scans (
          id TEXT PRIMARY KEY NOT NULL,
          scope_path TEXT NOT NULL,
          status INTEGER NOT NULL,
          started_at REAL NOT NULL,
          completed_at REAL
        );
        CREATE TABLE items (
          scan_id TEXT NOT NULL,
          item_id TEXT NOT NULL,
          parent_path TEXT,
          parent_item_id TEXT,
          path TEXT NOT NULL,
          name TEXT NOT NULL,
          kind INTEGER NOT NULL,
          allocated_bytes INTEGER,
          logical_bytes INTEGER,
          is_hidden INTEGER NOT NULL,
          is_root INTEGER NOT NULL DEFAULT 0,
          tree_depth INTEGER,
          aggregate_allocated_bytes INTEGER,
          aggregate_logical_bytes INTEGER,
          allocated_incomplete INTEGER NOT NULL DEFAULT 0,
          logical_incomplete INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (scan_id, item_id),
          UNIQUE (scan_id, path)
        );
        CREATE TABLE scan_issues (
          scan_id TEXT NOT NULL,
          path TEXT NOT NULL,
          kind INTEGER NOT NULL,
          message TEXT NOT NULL
        );
        PRAGMA user_version = 2;
        """,
        on: database
      )
      try SQLiteDatabase.withStatement(
        """
        INSERT INTO scans (id, scope_path, status, started_at, completed_at)
        VALUES (?, ?, 1, 0, 1);
        """,
        on: database
      ) { statement in
        try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 1, to: statement)
        try SQLiteDatabase.bind(scopeURL.path, at: 2, to: statement)
        try SQLiteDatabase.requireDone(statement)
      }
      try SQLiteDatabase.withStatement(
        """
        INSERT INTO items (
          scan_id, item_id, parent_path, parent_item_id, path, name, kind,
          allocated_bytes, logical_bytes, is_hidden, is_root, tree_depth,
          aggregate_allocated_bytes, aggregate_logical_bytes,
          allocated_incomplete, logical_incomplete
        ) VALUES (?, ?, NULL, NULL, ?, 'scope', 1, NULL, NULL, 0, 1, 0,
                  12, 12, 0, 0);
        """,
        on: database
      ) { statement in
        try SQLiteDatabase.bind(scan.rawValue.uuidString, at: 1, to: statement)
        try SQLiteDatabase.bind(rootID.uuidString, at: 2, to: statement)
        try SQLiteDatabase.bind(scopeURL.path, at: 3, to: statement)
        try SQLiteDatabase.requireDone(statement)
      }
    }
    return scan
  }

  func seedVersionThreeCandidateAndLegacyCompleted() throws -> (
    candidate: ScanID,
    completed: ScanID
  ) {
    let completed = try seedVersionTwoSnapshot()
    let candidate = ScanID(rawValue: UUID())
    let candidateRoot = UUID()
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try SQLiteDatabase.execute(
        """
        ALTER TABLE items ADD COLUMN is_package_descendant INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE items ADD COLUMN file_system_identity TEXT;
        ALTER TABLE items ADD COLUMN hard_link_count INTEGER;
        ALTER TABLE items ADD COLUMN is_shared INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE items ADD COLUMN is_cloud_only INTEGER NOT NULL DEFAULT 0;
        PRAGMA user_version = 3;
        """,
        on: database
      )
      try SQLiteDatabase.withStatement(
        """
        INSERT INTO scans (id, scope_path, status, started_at, completed_at)
        VALUES (?, ?, 0, 0, NULL);
        """,
        on: database
      ) { statement in
        try SQLiteDatabase.bind(candidate.rawValue.uuidString, at: 1, to: statement)
        try SQLiteDatabase.bind(scopeURL.path, at: 2, to: statement)
        try SQLiteDatabase.requireDone(statement)
      }
      try SQLiteDatabase.withStatement(
        """
        INSERT INTO items (
          scan_id, item_id, parent_path, parent_item_id, path, name, kind,
          allocated_bytes, logical_bytes, is_hidden, is_root, tree_depth,
          aggregate_allocated_bytes, aggregate_logical_bytes,
          allocated_incomplete, logical_incomplete
        ) VALUES (?, ?, NULL, NULL, ?, 'scope', 1, NULL, NULL, 0, 1, 0,
                  12, 12, 0, 0);
        """,
        on: database
      ) { statement in
        try SQLiteDatabase.bind(candidate.rawValue.uuidString, at: 1, to: statement)
        try SQLiteDatabase.bind(candidateRoot.uuidString, at: 2, to: statement)
        try SQLiteDatabase.bind(scopeURL.path, at: 3, to: statement)
        try SQLiteDatabase.requireDone(statement)
      }
    }
    return (candidate, completed)
  }

  func userVersion() throws -> Int {
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try SQLiteDatabase.withStatement(
        "PRAGMA user_version;",
        on: database
      ) { statement in
        guard sqlite3_step(statement) == SQLITE_ROW else {
          throw SnapshotIndexError.integrityCheckFailed
        }
        return Int(sqlite3_column_int64(statement, 0))
      }
    }
  }

  func seedVersionThreeDatabaseWithIncompatibleItemsView() throws {
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try SQLiteDatabase.execute(
        """
        CREATE TABLE scans (
          id TEXT PRIMARY KEY NOT NULL,
          scope_path TEXT NOT NULL,
          status INTEGER NOT NULL,
          started_at REAL NOT NULL,
          completed_at REAL
        );
        CREATE VIEW items AS SELECT id FROM scans;
        CREATE TABLE scan_issues (
          scan_id TEXT NOT NULL,
          path TEXT NOT NULL,
          kind INTEGER NOT NULL,
          message TEXT NOT NULL
        );
        PRAGMA user_version = 3;
        """,
        on: database
      )
    }
  }

  func scanColumnNames() throws -> Set<String> {
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try SQLiteDatabase.withStatement(
        "PRAGMA table_info(scans);",
        on: database
      ) { statement in
        var names: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
          guard let name = sqlite3_column_text(statement, 1) else {
            throw SnapshotIndexError.integrityCheckFailed
          }
          names.insert(String(cString: name))
        }
        return names
      }
    }
  }

  func installCompletedDeleteFailureTrigger() throws {
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try SQLiteDatabase.execute(
        """
        CREATE TRIGGER fail_completed_delete
        BEFORE DELETE ON scans
        WHEN OLD.status = 1
        BEGIN
          SELECT RAISE(FAIL, 'completed snapshot deletion failed');
        END;
        """,
        on: database
      )
    }
  }

  func removeCompletedDeleteFailureTrigger() throws {
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try SQLiteDatabase.execute(
        "DROP TRIGGER fail_completed_delete;",
        on: database
      )
    }
  }

  func seedIncompatibleDatabase() throws {
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try SQLiteDatabase.execute(
        """
        CREATE TABLE sentinel (value TEXT NOT NULL);
        INSERT INTO sentinel (value) VALUES ('old cache row');
        PRAGMA user_version = 999;
        """,
        on: database
      )
    }
    try writeCompanionFiles()
  }

  func writeCorruptDatabase() throws {
    try Data("not a sqlite database".utf8).write(to: databaseURL)
    try writeCompanionFiles()
  }

  private func writeCompanionFiles() throws {
    try Data("old wal".utf8).write(
      to: URL(fileURLWithPath: "\(databaseURL.path)-wal")
    )
    try Data("old shm".utf8).write(
      to: URL(fileURLWithPath: "\(databaseURL.path)-shm")
    )
  }
}

private final class MutableDateProvider: DateProviding, @unchecked Sendable {
  private let lock = NSLock()
  private var currentDate: Date

  init(now: Date) {
    currentDate = now
  }

  func now() -> Date {
    lock.withLock { currentDate }
  }

  func advance(to date: Date) {
    lock.withLock {
      currentDate = date
    }
  }
}

private final class SQLiteExclusiveLock {
  private var database: OpaquePointer?

  init(databaseURL: URL) throws {
    var openedDatabase: OpaquePointer?
    let openResult = sqlite3_open_v2(
      databaseURL.path(percentEncoded: false),
      &openedDatabase,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
      nil
    )
    guard openResult == SQLITE_OK, let openedDatabase else {
      if let openedDatabase {
        sqlite3_close(openedDatabase)
      }
      throw SnapshotIndexError.openFailed(code: openResult)
    }
    database = openedDatabase
    let result = sqlite3_exec(openedDatabase, "BEGIN EXCLUSIVE;", nil, nil, nil)
    guard result == SQLITE_OK else {
      sqlite3_close(openedDatabase)
      database = nil
      throw SnapshotIndexError.statementFailed(code: result)
    }
  }

  func release() {
    guard let database else {
      return
    }
    sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
    sqlite3_close(database)
    self.database = nil
  }

  deinit {
    release()
  }
}
