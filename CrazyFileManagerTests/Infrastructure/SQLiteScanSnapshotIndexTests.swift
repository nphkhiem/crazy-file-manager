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
  func givenAPromotedSnapshot_whenCacheFileSizeIsQueried_thenItReturnsARealNonZeroSize()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
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
    _ = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 1,
      expectedIssueCount: 0
    )

    let size = try await fixture.index.cacheFileSizeBytes()

    #expect((try #require(size)) > 0)
  }

  @Test
  func givenNoDatabaseFileYet_whenCacheFileSizeIsQueried_thenItReturnsNil() async throws {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }

    let size = try await fixture.index.cacheFileSizeBytes()

    #expect(size == nil)
  }

  @Test
  func
    givenPromotedScanWithAnItem_whenItemDetailIsQueried_thenFullRowAndVolumeCharacteristicsAreReturned()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
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
    let item = fixture.item(name: "report.pdf", diskUsedBytes: 4_096)
    try await fixture.index.append(fixture.batch(items: [item]), to: candidate)
    _ = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 1,
      expectedIssueCount: 0
    )

    let detail = try #require(try await fixture.index.itemDetail(for: item.id, in: candidate))

    #expect(detail.item.id == item.id)
    #expect(detail.item.name == "report.pdf")
    #expect(detail.item.kind == .file)
    #expect(detail.volumeCharacteristics.isInternal == true)
    #expect(detail.volumeCharacteristics.isReadOnly == false)
  }

  @Test
  func givenUnknownItemID_whenItemDetailIsQueried_thenNilIsReturned() async throws {
    let fixture = try TemporarySnapshotIndexFixture()
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
    _ = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )

    let detail = try await fixture.index.itemDetail(for: UUID(), in: candidate)

    #expect(detail == nil)
  }

  @Test
  func givenAPromotedScanWithIssues_whenIssuesAreQueried_thenTheyAreReturnedUpToTheLimit()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
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
    let item = fixture.item(name: "report.pdf", diskUsedBytes: 4_096)
    let firstIssue = fixture.issue(path: "first.bin")
    let secondIssue = fixture.issue(path: "second.bin")
    try await fixture.index.append(
      fixture.batch(items: [item], issues: [firstIssue, secondIssue]),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 1, issueCount: 2)

    let issues = try await fixture.index.issues(in: candidate, limit: 200)

    #expect(issues.count == 2)
    #expect(Set(issues.map(\.location.lastPathComponent)) == ["first.bin", "second.bin"])
    #expect(issues.allSatisfy { $0.kind == .accessDenied })
  }

  @Test
  func givenPromotedScanWithAnItem_whenItemNameIsUpdated_thenItemDetailReflectsTheNewNameAndPath()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
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
    let item = fixture.item(name: "report.pdf", diskUsedBytes: 4_096)
    try await fixture.index.append(fixture.batch(items: [item]), to: candidate)
    _ = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 1,
      expectedIssueCount: 0
    )
    let newPath = fixture.scopeURL.appending(path: "renamed.pdf").path(percentEncoded: false)

    try await fixture.index.updateItemName(
      item.id,
      in: candidate,
      newName: "renamed.pdf",
      newPath: newPath
    )

    let detail = try #require(try await fixture.index.itemDetail(for: item.id, in: candidate))
    #expect(detail.item.name == "renamed.pdf")
    #expect(detail.item.location.path(percentEncoded: false) == newPath)
  }

  @Test
  func givenALeafFile_whenDescendantCountIsQueried_thenItReturnsNil() async throws {
    let fixture = try TemporarySnapshotIndexFixture()
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
    let item = fixture.item(name: "report.pdf", diskUsedBytes: 4_096)
    try await fixture.index.append(fixture.batch(items: [item]), to: candidate)
    try await fixture.promote(candidate, itemCount: 1)

    let count = try await fixture.index.descendantCount(of: item.id, in: candidate)

    #expect(count == nil)
  }

  @Test
  func givenANestedFolder_whenDescendantCountIsQueried_thenItReturnsTheExactRecursiveCount()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
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
    let parent = fixture.folder(path: "documents")
    let child = fixture.file(path: "documents/notes.txt", diskUsedBytes: 10)
    let grandchildFolder = fixture.folder(path: "documents/nested")
    let grandchild = fixture.file(path: "documents/nested/deep.txt", diskUsedBytes: 5)
    try await fixture.index.append(
      fixture.batch(items: [parent, child, grandchildFolder, grandchild]),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 4)

    let count = try await fixture.index.descendantCount(of: parent.id, in: candidate)

    #expect(count == 3)
  }

  @Test
  func givenALeafFile_whenItemIsRemoved_thenItemDetailReturnsNilAfterward() async throws {
    let fixture = try TemporarySnapshotIndexFixture()
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
    let item = fixture.item(name: "report.pdf", diskUsedBytes: 4_096)
    try await fixture.index.append(fixture.batch(items: [item]), to: candidate)
    try await fixture.promote(candidate, itemCount: 1)

    try await fixture.index.removeItem(item.id, in: candidate)

    let detail = try await fixture.index.itemDetail(for: item.id, in: candidate)
    #expect(detail == nil)
  }

  @Test
  func givenANestedFolder_whenItemIsRemoved_thenTheFolderAndEveryDescendantAreGone() async throws {
    let fixture = try TemporarySnapshotIndexFixture()
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
    let parent = fixture.folder(path: "documents")
    let child = fixture.file(path: "documents/notes.txt", diskUsedBytes: 10)
    let grandchildFolder = fixture.folder(path: "documents/nested")
    let grandchild = fixture.file(path: "documents/nested/deep.txt", diskUsedBytes: 5)
    try await fixture.index.append(
      fixture.batch(items: [parent, child, grandchildFolder, grandchild]),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 4)

    try await fixture.index.removeItem(parent.id, in: candidate)

    for removedID in [parent.id, child.id, grandchildFolder.id, grandchild.id] {
      let detail = try await fixture.index.itemDetail(for: removedID, in: candidate)
      #expect(detail == nil)
    }
  }

  @Test
  func
    givenPromotedScanWithANestedChild_whenTheParentFolderIsRenamed_thenTheChildsCachedPathReflectsTheNewFolderName()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
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
    let folder = fixture.folder(path: "documents")
    let child = fixture.file(
      path: "documents/report.pdf",
      diskUsedBytes: 4_096,
      apparentSizeBytes: 4_096
    )
    try await fixture.index.append(fixture.batch(items: [folder, child]), to: candidate)
    _ = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 2,
      expectedIssueCount: 0
    )
    let newFolderPath = fixture.scopeURL
      .appending(path: "archive", directoryHint: .isDirectory)
      .path(percentEncoded: false)

    try await fixture.index.updateItemName(
      folder.id,
      in: candidate,
      newName: "archive",
      newPath: newFolderPath
    )

    let childDetail = try #require(
      try await fixture.index.itemDetail(for: child.id, in: candidate)
    )
    let expectedChildPath = fixture.scopeURL
      .appending(path: "archive/report.pdf", directoryHint: .notDirectory)
      .path(percentEncoded: false)
    #expect(childDetail.item.name == "report.pdf")
    #expect(childDetail.item.location.path(percentEncoded: false) == expectedChildPath)
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
  func givenTwoPromotions_whenFlatItemsIsQueried_thenOnlyTheSecondSnapshotsItemsAreReturned()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let first = try await fixture.index.beginCandidate(for: scope)
    try await fixture.index.append(
      fixture.batch(items: [
        fixture.file(path: "first.bin", diskUsedBytes: 10, apparentSizeBytes: 10)
      ]),
      to: first
    )
    try await fixture.promote(first, itemCount: 1)
    let second = try await fixture.index.beginCandidate(for: scope)
    try await fixture.index.append(
      fixture.batch(items: [
        fixture.file(path: "second.bin", diskUsedBytes: 20, apparentSizeBytes: 20)
      ]),
      to: second
    )
    try await fixture.promote(second, itemCount: 1)

    let page = try await fixture.index.flatItems(
      in: second,
      query: AllItemsQuery(),
      offset: 0,
      limit: 10
    )

    #expect(page.items.map(\.name) == ["second.bin"])
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await fixture.index.treeRoot(in: first)
    }
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
    #expect(try fixture.userVersion() == 7)
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
    #expect(try fixture.userVersion() == 7)
  }

  @Test
  func
    givenVersionFourCompletedSnapshot_whenIndexOpensAndMigratesForward_thenTheSnapshotIsDiscarded()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let completed = try fixture.seedVersionFourCompletedSnapshot()
    let relaunchedIndex = SQLiteScanSnapshotIndex(
      databaseURL: fixture.databaseURL
    )

    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await relaunchedIndex.treeRoot(in: completed)
    }
    #expect(try fixture.userVersion() == 7)

    let freshCandidate = try await relaunchedIndex.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    try await relaunchedIndex.append(
      fixture.batch(items: [fixture.item(name: "after-migration.bin", diskUsedBytes: 10)]),
      to: freshCandidate
    )
    let promoted = try await relaunchedIndex.promoteCandidate(
      freshCandidate,
      expectedItemCount: 1,
      expectedIssueCount: 0
    )
    #expect(promoted.scanID == freshCandidate)
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
  func givenAFileWithAKnownModifiedDate_whenTreeQueriesReturnIt_thenModifiedAtIsPopulated()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let knownDate = Date(timeIntervalSince1970: 1_700_000_000)
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    try await fixture.index.append(
      fixture.batch(
        items: [
          fixture.file(
            path: "timestamped.bin",
            diskUsedBytes: 10,
            apparentSizeBytes: 10,
            modifiedAt: knownDate
          )
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 1)
    let root = try await fixture.index.treeRoot(in: candidate)
    let rootPage = try await fixture.index.directChildren(
      of: root.id,
      in: candidate,
      offset: 0,
      limit: 20
    )
    let fileRow = try #require(rootPage.items.first { $0.name == "timestamped.bin" })
    let detail = try #require(
      try await fixture.index.itemDetail(for: fileRow.id, in: candidate)
    )

    let rowModifiedAt = try #require(fileRow.modifiedAt)
    #expect(abs(rowModifiedAt.timeIntervalSince(knownDate)) < 1)
    let detailModifiedAt = try #require(detail.item.modifiedAt)
    #expect(abs(detailModifiedAt.timeIntervalSince(knownDate)) < 1)
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
  func givenMoreItemsThanOnePage_whenFlatItemsIsPaged_thenOrderIsStableAndNextOffsetIsCorrect()
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
          fixture.file(path: "a.bin", diskUsedBytes: 40, apparentSizeBytes: 40),
          fixture.file(path: "b.bin", diskUsedBytes: 30, apparentSizeBytes: 30),
          fixture.file(path: "c.bin", diskUsedBytes: 30, apparentSizeBytes: 30),
          fixture.file(path: "d.bin", diskUsedBytes: 10, apparentSizeBytes: 10),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 4)

    let fullPage = try await fixture.index.flatItems(
      in: candidate,
      query: AllItemsQuery(),
      offset: 0,
      limit: 10
    )
    let firstPage = try await fixture.index.flatItems(
      in: candidate,
      query: AllItemsQuery(),
      offset: 0,
      limit: 2
    )
    let secondPage = try await fixture.index.flatItems(
      in: candidate,
      query: AllItemsQuery(),
      offset: 2,
      limit: 2
    )

    #expect(fullPage.items.map(\.name).first == "a.bin")
    #expect(fullPage.items.map(\.name).last == "d.bin")
    #expect(Set(fullPage.items.map(\.name)) == ["a.bin", "b.bin", "c.bin", "d.bin"])
    #expect(fullPage.nextOffset == nil)
    #expect(firstPage.items.map(\.name) == Array(fullPage.items.prefix(2)).map(\.name))
    #expect(firstPage.nextOffset == 2)
    #expect(secondPage.items.map(\.name) == Array(fullPage.items.suffix(2)).map(\.name))
    #expect(secondPage.nextOffset == nil)
  }

  @Test
  func givenItemsOfDifferentKinds_whenFlatItemsFiltersByKind_thenOnlyMatchingKindIsReturned()
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
          fixture.folder(path: "Folder"),
          fixture.file(path: "file.bin", diskUsedBytes: 10, apparentSizeBytes: 10),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 2)

    var query = AllItemsQuery()
    query.filters.kinds = [.folder]
    let page = try await fixture.index.flatItems(
      in: candidate,
      query: query,
      offset: 0,
      limit: 10
    )

    #expect(page.items.map(\.name) == ["Folder"])
  }

  @Test
  func
    givenHiddenAndVisibleItems_whenFlatItemsFiltersByHiddenState_thenOnlyMatchingStateIsReturned()
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
            path: "visible.bin",
            diskUsedBytes: 10,
            apparentSizeBytes: 10,
            isHidden: false
          ),
          fixture.file(
            path: ".hidden.bin",
            diskUsedBytes: 10,
            apparentSizeBytes: 10,
            isHidden: true
          ),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 2)

    var onlyHidden = AllItemsQuery()
    onlyHidden.filters.hidden = .onlyTrue
    let hiddenPage = try await fixture.index.flatItems(
      in: candidate,
      query: onlyHidden,
      offset: 0,
      limit: 10
    )
    var onlyVisible = AllItemsQuery()
    onlyVisible.filters.hidden = .onlyFalse
    let visiblePage = try await fixture.index.flatItems(
      in: candidate,
      query: onlyVisible,
      offset: 0,
      limit: 10
    )

    #expect(hiddenPage.items.map(\.name) == [".hidden.bin"])
    #expect(visiblePage.items.map(\.name) == ["visible.bin"])
  }

  @Test
  func
    givenCloudOnlyAndLocalItems_whenFlatItemsFiltersByCloudOnlyState_thenOnlyMatchingStateIsReturned()
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
            path: "local.bin",
            diskUsedBytes: 10,
            apparentSizeBytes: 10,
            isCloudOnly: false
          ),
          fixture.file(
            path: "cloud.bin",
            diskUsedBytes: 10,
            apparentSizeBytes: 10,
            isCloudOnly: true
          ),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 2)

    var onlyCloud = AllItemsQuery()
    onlyCloud.filters.cloudOnly = .onlyTrue
    let cloudPage = try await fixture.index.flatItems(
      in: candidate,
      query: onlyCloud,
      offset: 0,
      limit: 10
    )

    #expect(cloudPage.items.map(\.name) == ["cloud.bin"])
  }

  @Test
  func
    givenItemsWithDifferentSizes_whenFlatItemsFiltersByMinimumDiskUsed_thenSmallerItemsAreExcluded()
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
          fixture.file(path: "small.bin", diskUsedBytes: 5, apparentSizeBytes: 5),
          fixture.file(path: "large.bin", diskUsedBytes: 50, apparentSizeBytes: 50),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 2)

    var query = AllItemsQuery()
    query.filters.minimumDiskUsedBytes = 10
    let page = try await fixture.index.flatItems(
      in: candidate,
      query: query,
      offset: 0,
      limit: 10
    )

    #expect(page.items.map(\.name) == ["large.bin"])
  }

  @Test
  func
    givenMultipleFilterDimensions_whenFlatItemsAppliesThemTogether_thenOnlyItemsMatchingAllApply()
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
            path: "visible-small.bin",
            diskUsedBytes: 5,
            apparentSizeBytes: 5,
            isHidden: false
          ),
          fixture.file(
            path: ".hidden-small.bin",
            diskUsedBytes: 5,
            apparentSizeBytes: 5,
            isHidden: true
          ),
          fixture.file(
            path: ".hidden-large.bin",
            diskUsedBytes: 50,
            apparentSizeBytes: 50,
            isHidden: true
          ),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 3)

    var query = AllItemsQuery()
    query.filters.hidden = .onlyTrue
    query.filters.minimumDiskUsedBytes = 10
    let page = try await fixture.index.flatItems(
      in: candidate,
      query: query,
      offset: 0,
      limit: 10
    )

    #expect(page.items.map(\.name) == [".hidden-large.bin"])
  }

  @Test
  func
    givenARootAndAPackageWithDescendants_whenFlatItemsIsQueried_thenRootAndPackageDescendantsAreExcluded()
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
          fixture.package(path: "Sample.app", diskUsedBytes: 100),
          fixture.folder(path: "Sample.app/Contents"),
          fixture.file(
            path: "Sample.app/Contents/payload.bin",
            diskUsedBytes: 100,
            apparentSizeBytes: 100
          ),
          fixture.file(path: "visible.bin", diskUsedBytes: 10, apparentSizeBytes: 10),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 4)

    let page = try await fixture.index.flatItems(
      in: candidate,
      query: AllItemsQuery(),
      offset: 0,
      limit: 10
    )

    #expect(Set(page.items.map(\.name)) == ["Sample.app", "visible.bin"])
  }

  @Test
  func givenANonAsciiCasedName_whenFlatItemsSearches_thenItMatchesCaseInsensitively()
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
          fixture.file(path: "ÉCLAIR.bin", diskUsedBytes: 10, apparentSizeBytes: 10),
          fixture.file(path: "other.bin", diskUsedBytes: 10, apparentSizeBytes: 10),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 2)

    var query = AllItemsQuery()
    query.searchText = "éclair"
    let page = try await fixture.index.flatItems(
      in: candidate,
      query: query,
      offset: 0,
      limit: 10
    )

    #expect(page.items.map(\.name) == ["ÉCLAIR.bin"])
  }

  @Test
  func givenASearchTermMatchingOnlyThePath_whenFlatItemsSearches_thenTheItemIsFound()
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
          fixture.folder(path: "notes"),
          fixture.file(path: "notes/report.pdf", diskUsedBytes: 10, apparentSizeBytes: 10),
          fixture.file(path: "unrelated.bin", diskUsedBytes: 10, apparentSizeBytes: 10),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 3)

    var query = AllItemsQuery()
    query.searchText = "notes"
    query.filters.kinds = [.file]
    let page = try await fixture.index.flatItems(
      in: candidate,
      query: query,
      offset: 0,
      limit: 10
    )

    #expect(page.items.map(\.name) == ["report.pdf"])
  }

  @Test
  func givenItemsWithDistinctValues_whenFlatItemsSortsByEachField_thenOrderMatchesTheField()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    let earliest = Date(timeIntervalSince1970: 1_700_000_000)
    let middle = Date(timeIntervalSince1970: 1_700_000_100)
    let latest = Date(timeIntervalSince1970: 1_700_000_200)
    try await fixture.index.append(
      fixture.batch(
        items: [
          fixture.file(
            path: "alpha.bin",
            diskUsedBytes: 30,
            apparentSizeBytes: 10,
            modifiedAt: middle
          ),
          fixture.file(
            path: "beta.bin",
            diskUsedBytes: 10,
            apparentSizeBytes: 30,
            modifiedAt: earliest
          ),
          fixture.file(
            path: "gamma.bin",
            diskUsedBytes: 20,
            apparentSizeBytes: 20,
            modifiedAt: latest
          ),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 3)

    func names(field: AllItemsSortField, direction: SortDirection) async throws -> [String] {
      var query = AllItemsQuery()
      query.sort = AllItemsSort(field: field, direction: direction)
      let page = try await fixture.index.flatItems(
        in: candidate,
        query: query,
        offset: 0,
        limit: 10
      )
      return page.items.map(\.name)
    }

    #expect(
      try await names(field: .diskUsed, direction: .descending) == [
        "alpha.bin", "gamma.bin", "beta.bin",
      ])
    #expect(
      try await names(field: .diskUsed, direction: .ascending) == [
        "beta.bin", "gamma.bin", "alpha.bin",
      ])
    #expect(
      try await names(field: .apparentSize, direction: .descending) == [
        "beta.bin", "gamma.bin", "alpha.bin",
      ])
    #expect(
      try await names(field: .apparentSize, direction: .ascending) == [
        "alpha.bin", "gamma.bin", "beta.bin",
      ])
    #expect(
      try await names(field: .name, direction: .ascending) == [
        "alpha.bin", "beta.bin", "gamma.bin",
      ])
    #expect(
      try await names(field: .name, direction: .descending) == [
        "gamma.bin", "beta.bin", "alpha.bin",
      ])
    #expect(
      try await names(field: .modifiedAt, direction: .descending) == [
        "gamma.bin", "alpha.bin", "beta.bin",
      ])
    #expect(
      try await names(field: .modifiedAt, direction: .ascending) == [
        "beta.bin", "alpha.bin", "gamma.bin",
      ])
  }

  @Test
  func givenItemsInDifferentFolders_whenFlatItemsSortsByPath_thenOrderFollowsFullPath()
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
          fixture.folder(path: "alpha-folder"),
          fixture.folder(path: "zulu-folder"),
          fixture.file(
            path: "alpha-folder/item.bin",
            diskUsedBytes: 10,
            apparentSizeBytes: 10
          ),
          fixture.file(
            path: "zulu-folder/item.bin",
            diskUsedBytes: 10,
            apparentSizeBytes: 10
          ),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 4)

    var ascending = AllItemsQuery()
    ascending.filters.kinds = [.file]
    ascending.sort = AllItemsSort(field: .path, direction: .ascending)
    let ascendingPage = try await fixture.index.flatItems(
      in: candidate,
      query: ascending,
      offset: 0,
      limit: 10
    )
    var descending = AllItemsQuery()
    descending.filters.kinds = [.file]
    descending.sort = AllItemsSort(field: .path, direction: .descending)
    let descendingPage = try await fixture.index.flatItems(
      in: candidate,
      query: descending,
      offset: 0,
      limit: 10
    )

    #expect(
      ascendingPage.items.map { $0.location.path(percentEncoded: false) }
        == [
          fixture.scopeURL.appending(path: "alpha-folder/item.bin").path(percentEncoded: false),
          fixture.scopeURL.appending(path: "zulu-folder/item.bin").path(percentEncoded: false),
        ]
    )
    #expect(
      descendingPage.items.map { $0.location.path(percentEncoded: false) }
        == [
          fixture.scopeURL.appending(path: "zulu-folder/item.bin").path(percentEncoded: false),
          fixture.scopeURL.appending(path: "alpha-folder/item.bin").path(percentEncoded: false),
        ]
    )
  }

  @Test
  func givenAnItemWithUnknownDiskUsedAndModifiedDate_whenSorted_thenItSortsLastInBothDirections()
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
          fixture.file(path: "known-small.bin", diskUsedBytes: 5, apparentSizeBytes: 5),
          fixture.file(path: "known-large.bin", diskUsedBytes: 50, apparentSizeBytes: 50),
          fixture.file(path: "unknown.bin", diskUsedBytes: nil, apparentSizeBytes: nil),
        ]
      ),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 3)

    var descending = AllItemsQuery()
    descending.sort = AllItemsSort(field: .diskUsed, direction: .descending)
    let descendingPage = try await fixture.index.flatItems(
      in: candidate,
      query: descending,
      offset: 0,
      limit: 10
    )
    var ascending = AllItemsQuery()
    ascending.sort = AllItemsSort(field: .diskUsed, direction: .ascending)
    let ascendingPage = try await fixture.index.flatItems(
      in: candidate,
      query: ascending,
      offset: 0,
      limit: 10
    )

    #expect(descendingPage.items.map(\.name).last == "unknown.bin")
    #expect(ascendingPage.items.map(\.name).last == "unknown.bin")
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

  @Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_STRESS_BENCHMARK"] == "1"))
  func givenALargeCandidateAndAMidPromotionFailure_whenPromotionFails_thenThePriorSnapshotSurvives()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let priorScanner = SyntheticFileSystemScanner(
      totalItemCount: 100_000,
      scopeURL: fixture.scopeURL
    )
    let priorCandidate = try await fixture.index.beginCandidate(for: scope)
    for try await batch in await priorScanner.batches(for: scope) {
      try await fixture.index.append(batch, to: priorCandidate)
    }
    try await fixture.promote(priorCandidate, itemCount: 100_000)

    let failingScanner = SyntheticFileSystemScanner(
      totalItemCount: 100_000,
      scopeURL: fixture.scopeURL
    )
    let failingCandidate = try await fixture.index.beginCandidate(for: scope)
    for try await batch in await failingScanner.batches(for: scope) {
      try await fixture.index.append(batch, to: failingCandidate)
    }

    await #expect(throws: SnapshotIndexError.self) {
      try await fixture.index.promoteCandidate(
        failingCandidate,
        expectedItemCount: 100_000 + 1,
        expectedIssueCount: 0
      )
    }

    let survivingRoot = try await fixture.index.treeRoot(in: priorCandidate)
    #expect(survivingRoot.isRoot)
    let survivingPage = try await fixture.index.directChildren(
      of: survivingRoot.id,
      in: priorCandidate,
      offset: 0,
      limit: 1
    )
    #expect(survivingPage.items.count == 1)
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

  @Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_STRESS_BENCHMARK"] == "1"))
  func givenALargeCrashLeftoverCandidate_whenPreparingCacheForLaunch_thenItIsRemovedWithoutHanging()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let completed = try await fixture.index.beginCandidate(for: scope)
    try await fixture.promote(completed, itemCount: 0)
    let crashLeftover = try await fixture.index.beginCandidate(for: scope)
    let scanner = SyntheticFileSystemScanner(totalItemCount: 200_000, scopeURL: fixture.scopeURL)
    for try await batch in await scanner.batches(for: scope) {
      try await fixture.index.append(batch, to: crashLeftover)
    }
    let relaunchedIndex = SQLiteScanSnapshotIndex(databaseURL: fixture.databaseURL)

    let clock = ContinuousClock()
    let start = clock.now
    try await relaunchedIndex.removeCrashLeftoverCandidates()
    let elapsed = clock.now - start

    #expect(try await relaunchedIndex.treeRoot(in: completed).isRoot)
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await relaunchedIndex.largestItems(in: crashLeftover, limit: 10)
    }
    #expect(elapsed < .seconds(10))
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_STRESS_BENCHMARK"] == "1"))
  func
    givenALargeCandidateWithOneInaccessibleItem_whenPromoted_thenRootRemainsHonestlyIncomplete()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let candidate = try await fixture.index.beginCandidate(for: scope)
    let scanner = SyntheticFileSystemScanner(totalItemCount: 200_000, scopeURL: fixture.scopeURL)
    for try await batch in await scanner.batches(for: scope) {
      try await fixture.index.append(batch, to: candidate)
    }
    try await fixture.index.append(
      fixture.batch(items: [], issues: [fixture.issue(path: "restricted")]),
      to: candidate
    )

    try await fixture.promote(candidate, itemCount: 200_000, issueCount: 1)
    let root = try await fixture.index.treeRoot(in: candidate)

    #expect(root.isDiskUsedIncomplete)
    #expect(root.isApparentSizeIncomplete)
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
  func
    givenCompletedSnapshotWithMissingRequiredMetadata_whenPreparingCacheForLaunch_thenDatabaseIsReconstructedWithoutOldProjection()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let fixture = try TemporarySnapshotIndexFixture(
      dateProvider: MutableDateProvider(now: completedAt)
    )
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    let promoted = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )
    try fixture.removeRequiredCompletedMetadata()

    let preparation = try await fixture.index.prepareCacheForLaunch(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    #expect(preparation == .reconstructed)
    #expect(try fixture.userVersion() == 7)
    #expect(
      try await fixture.index.prepareCacheForLaunch(
        largestItemLimit: 1,
        treePageLimit: 1
      ) == .empty
    )
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await fixture.index.treeRoot(in: promoted.scanID)
    }
  }

  @Test
  func
    givenCompletedSnapshotWithMissingRequiredMetadata_whenRefreshingCache_thenDatabaseIsReconstructedWithoutOldProjection()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let fixture = try TemporarySnapshotIndexFixture(
      dateProvider: MutableDateProvider(now: completedAt)
    )
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    let promoted = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )
    try fixture.removeRequiredCompletedMetadata()

    let preparation = try await fixture.index.refreshCompletedCache(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    #expect(preparation == .reconstructed)
    #expect(try fixture.userVersion() == 7)
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await fixture.index.treeRoot(in: promoted.scanID)
    }
  }

  @Test
  func
    givenVersionFourDatabaseFailsIntegrityCheck_whenPreparingCacheForLaunch_thenDatabaseIsReconstructed()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    #expect(
      try await fixture.index.prepareCacheForLaunch(
        largestItemLimit: 1,
        treePageLimit: 1
      ) == .empty
    )
    try fixture.makeIntegrityCheckFail()

    let preparation = try await fixture.index.prepareCacheForLaunch(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    #expect(preparation == .reconstructed)
    #expect(try fixture.userVersion() == 7)
    #expect(
      try await fixture.index.prepareCacheForLaunch(
        largestItemLimit: 1,
        treePageLimit: 1
      ) == .empty
    )
  }

  @Test
  func
    givenCompletedSnapshotWithFarFutureExpiry_whenPreparingCacheForLaunch_thenDatabaseIsReconstructedWithoutReturningProjection()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let fixture = try TemporarySnapshotIndexFixture(
      dateProvider: MutableDateProvider(now: completedAt)
    )
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    let promoted = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )
    try fixture.replaceCompletedExpiry(with: 1e100)

    let preparation = try await fixture.index.prepareCacheForLaunch(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    #expect(preparation == .reconstructed)
    #expect(try fixture.userVersion() == 7)
    await #expect(throws: SnapshotIndexError.candidateNotFound) {
      try await fixture.index.treeRoot(in: promoted.scanID)
    }
  }

  @Test
  func
    givenCompletedSnapshotWithNonFiniteExpiry_whenPreparingCacheForLaunch_thenDatabaseIsReconstructedWithoutReturningProjection()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let fixture = try TemporarySnapshotIndexFixture(
      dateProvider: MutableDateProvider(now: completedAt)
    )
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    let promoted = try await fixture.index.promoteCandidate(
      candidate,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )
    try fixture.replaceCompletedExpiry(with: .infinity)

    let preparation = try await fixture.index.prepareCacheForLaunch(
      largestItemLimit: 1,
      treePageLimit: 1
    )

    #expect(preparation == .reconstructed)
    #expect(try fixture.userVersion() == 7)
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
    #expect(try fixture.userVersion() == 7)
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
    givenIncompatibleCacheWithCompanions_whenPreparingCacheForLaunch_thenExactCacheFilesAreReplacedAndUnrelatedFileRemains()
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
    #expect(try fixture.userVersion() == 7)
    #expect(FileManager.default.fileExists(atPath: fixture.databaseURL.path))
    #expect(
      fixture.exactCompanionURLs.allSatisfy {
        !fixture.fileSystemEntryExists(at: $0)
      }
    )
    #expect(FileManager.default.fileExists(atPath: fixture.unrelatedCacheURL.path))
    #expect(try Data(contentsOf: fixture.unrelatedCacheURL) == Data("unrelated".utf8))
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
    #expect(try fixture.userVersion() == 7)
    #expect(
      try await fixture.index.prepareCacheForLaunch(
        largestItemLimit: 1,
        treePageLimit: 1
      ) == .empty
    )
    #expect(!FileManager.default.fileExists(atPath: "\(fixture.databaseURL.path)-wal"))
    #expect(!FileManager.default.fileExists(atPath: "\(fixture.databaseURL.path)-shm"))
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_STRESS_BENCHMARK"] == "1"))
  func givenALargeCorruptDatabase_whenPreparingCacheForLaunch_thenItReconstructsWithoutHanging()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let scanner = SyntheticFileSystemScanner(totalItemCount: 200_000, scopeURL: fixture.scopeURL)
    let candidate = try await fixture.index.beginCandidate(for: scope)
    for try await batch in await scanner.batches(for: scope) {
      try await fixture.index.append(batch, to: candidate)
    }
    try await fixture.promote(candidate, itemCount: 200_000)

    let handle = try FileHandle(forWritingTo: fixture.databaseURL)
    try handle.truncate(atOffset: 4_096)
    try handle.close()

    let clock = ContinuousClock()
    let start = clock.now
    let preparation = try await fixture.index.prepareCacheForLaunch(
      largestItemLimit: 1,
      treePageLimit: 1
    )
    let elapsed = clock.now - start

    #expect(preparation == .reconstructed)
    #expect(try fixture.userVersion() == 7)
    #expect(elapsed < .seconds(10))
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
    #expect(try fixture.userVersion() == 7)
    #expect(try await fixture.index.treeRoot(in: candidate).isRoot)
  }

  @Test
  func
    givenManyItemsAcrossAllSortFields_whenFlatItemsQueries_thenResultsAreIdenticalRegardlessOfIndexPresence()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    let baseDate = try #require(ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z"))
    let items = (0..<500).map { index -> ScannedItem in
      fixture.file(
        path: "item-\(String(format: "%04d", index)).bin",
        diskUsedBytes: Int64(index % 97),
        apparentSizeBytes: Int64(index % 89),
        modifiedAt: baseDate.addingTimeInterval(Double(index % 53) * 3_600)
      )
    }
    try await fixture.index.append(fixture.batch(items: items), to: candidate)
    try await fixture.promote(candidate, itemCount: 500)

    for field in [
      AllItemsSortField.diskUsed, .apparentSize, .name, .modifiedAt, .path,
    ] {
      for direction in [SortDirection.ascending, .descending] {
        var query = AllItemsQuery()
        query.sort = AllItemsSort(field: field, direction: direction)
        let page = try await fixture.index.flatItems(
          in: candidate,
          query: query,
          offset: 0,
          limit: 1_000
        )
        #expect(page.items.count == 500)
        let orderedIDs = page.items.map(\.id)
        #expect(
          Set(orderedIDs).count == 500,
          "sort field \(field) direction \(direction) lost or duplicated rows"
        )
      }
    }
  }

  @Test
  func
    givenAnExistingVersionFiveDatabaseWithACompletedSnapshot_whenReopened_thenTheSnapshotSurvivesAndIndexesExist()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    try await fixture.index.append(
      fixture.batch(items: [fixture.item(name: "report.pdf", diskUsedBytes: 10)]),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 1)

    try SQLiteDatabase.withConnection(at: fixture.databaseURL) { database in
      for indexName in [
        "items_flat_name", "items_flat_path", "items_flat_modified",
        "items_flat_allocated", "items_flat_logical", "items_flat_kind",
      ] {
        try SQLiteDatabase.execute("DROP INDEX IF EXISTS \(indexName);", on: database)
      }
      try SQLiteDatabase.execute("PRAGMA user_version = 5;", on: database)
    }
    #expect(try fixture.userVersion() == 5)

    let relaunchedIndex = SQLiteScanSnapshotIndex(databaseURL: fixture.databaseURL)
    let preparation = try await relaunchedIndex.prepareCacheForLaunch(
      largestItemLimit: 10,
      treePageLimit: 10
    )

    guard case .available(let snapshot) = preparation else {
      Issue.record("Expected .available, got \(preparation)")
      return
    }
    #expect(snapshot.rootPage.items.map(\.name) == ["report.pdf"])
    #expect(try fixture.userVersion() == 7)
    let indexExistence = try SQLiteDatabase.withConnection(at: fixture.databaseURL) { database in
      try [
        "items_flat_name", "items_flat_path", "items_flat_modified",
        "items_flat_allocated", "items_flat_logical", "items_flat_kind",
      ].map { indexName -> Bool in
        try SQLiteDatabase.withStatement(
          "SELECT 1 FROM sqlite_master WHERE name = ? LIMIT 1;",
          on: database
        ) { statement in
          try SQLiteDatabase.bind(indexName, at: 1, to: statement)
          return sqlite3_step(statement) == SQLITE_ROW
        }
      }
    }
    #expect(indexExistence == [true, true, true, true, true, true])
  }

  @Test
  func
    givenAnExistingVersionSixDatabaseWithACompletedSnapshot_whenReopened_thenTheSnapshotSurvivesAndTrimmedPathIndexExists()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let candidate = try await fixture.index.beginCandidate(
      for: .homeFolder(fixture.scopeURL)
    )
    try await fixture.index.append(
      fixture.batch(items: [fixture.item(name: "report.pdf", diskUsedBytes: 10)]),
      to: candidate
    )
    try await fixture.promote(candidate, itemCount: 1)

    try SQLiteDatabase.withConnection(at: fixture.databaseURL) { database in
      try SQLiteDatabase.execute("DROP INDEX IF EXISTS items_path_trimmed;", on: database)
      try SQLiteDatabase.execute("PRAGMA user_version = 6;", on: database)
    }
    #expect(try fixture.userVersion() == 6)

    let relaunchedIndex = SQLiteScanSnapshotIndex(databaseURL: fixture.databaseURL)
    let preparation = try await relaunchedIndex.prepareCacheForLaunch(
      largestItemLimit: 10,
      treePageLimit: 10
    )

    guard case .available(let snapshot) = preparation else {
      Issue.record("Expected .available, got \(preparation)")
      return
    }
    #expect(snapshot.rootPage.items.map(\.name) == ["report.pdf"])
    #expect(try fixture.userVersion() == 7)
    let indexExists = try SQLiteDatabase.withConnection(at: fixture.databaseURL) { database in
      try SQLiteDatabase.withStatement(
        "SELECT 1 FROM sqlite_master WHERE name = ? LIMIT 1;",
        on: database
      ) { statement in
        try SQLiteDatabase.bind("items_path_trimmed", at: 1, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
      }
    }
    #expect(indexExists)
  }
}

struct TemporarySnapshotIndexFixture {
  let directoryURL: URL
  let databaseURL: URL
  let scopeURL: URL
  let index: SQLiteScanSnapshotIndex

  var exactCompanionURLs: [URL] {
    ["-journal", "-wal", "-shm"].map {
      URL(fileURLWithPath: "\(databaseURL.path)\($0)")
    }
  }

  var unrelatedCacheURL: URL {
    directoryURL.appending(path: "snapshot.sqlite-unrelated")
  }

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
    hardLinkCount: Int? = nil,
    modifiedAt: Date? = nil
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
      hardLinkCount: hardLinkCount,
      modifiedAt: modifiedAt
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

  func seedVersionFourCompletedSnapshot() throws -> ScanID {
    let completed = ScanID(rawValue: UUID())
    let rootID = UUID()
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try SQLiteDatabase.execute(
        """
        CREATE TABLE scans (
          id TEXT PRIMARY KEY NOT NULL,
          scope_path TEXT NOT NULL,
          status INTEGER NOT NULL,
          started_at REAL NOT NULL,
          completed_at REAL,
          scope_kind INTEGER NOT NULL,
          scope_volume_identity TEXT NOT NULL,
          scope_is_internal INTEGER,
          scope_is_read_only INTEGER,
          scope_is_removable INTEGER,
          snapshot_schema_version INTEGER,
          expires_at REAL
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
          is_package_descendant INTEGER NOT NULL DEFAULT 0,
          file_system_identity TEXT,
          hard_link_count INTEGER,
          is_shared INTEGER NOT NULL DEFAULT 0,
          is_cloud_only INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (scan_id, item_id),
          UNIQUE (scan_id, path)
        );
        CREATE TABLE scan_issues (
          scan_id TEXT NOT NULL,
          path TEXT NOT NULL,
          kind INTEGER NOT NULL,
          message TEXT NOT NULL
        );
        PRAGMA user_version = 4;
        """,
        on: database
      )
      try SQLiteDatabase.withStatement(
        """
        INSERT INTO scans (
          id, scope_path, status, started_at, completed_at,
          scope_kind, scope_volume_identity, scope_is_internal,
          scope_is_read_only, scope_is_removable, snapshot_schema_version, expires_at
        ) VALUES (?, ?, 1, 0, 1, 0, 'STABLE-VOLUME', 1, 0, 0, 4, NULL);
        """,
        on: database
      ) { statement in
        try SQLiteDatabase.bind(completed.rawValue.uuidString, at: 1, to: statement)
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
        try SQLiteDatabase.bind(completed.rawValue.uuidString, at: 1, to: statement)
        try SQLiteDatabase.bind(rootID.uuidString, at: 2, to: statement)
        try SQLiteDatabase.bind(scopeURL.path, at: 3, to: statement)
        try SQLiteDatabase.requireDone(statement)
      }
    }
    return completed
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

  func scanRowCount() throws -> Int {
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try SQLiteDatabase.withStatement(
        "SELECT COUNT(*) FROM scans;",
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

  func removeRequiredCompletedMetadata() throws {
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try SQLiteDatabase.execute(
        "UPDATE scans SET snapshot_schema_version = NULL WHERE status = 1;",
        on: database
      )
    }
  }

  func makeIntegrityCheckFail() throws {
    var database = try Data(contentsOf: databaseURL)
    database.replaceSubrange(36..<40, with: [0, 0, 0, 1])
    try database.write(to: databaseURL)
  }

  func replaceCompletedExpiry(with interval: TimeInterval) throws {
    try SQLiteDatabase.withConnection(at: databaseURL) { database in
      try SQLiteDatabase.withStatement(
        "UPDATE scans SET expires_at = ? WHERE status = 1;",
        on: database
      ) { statement in
        try SQLiteDatabase.requireSuccess(
          sqlite3_bind_double(statement, 1, interval)
        )
        try SQLiteDatabase.requireDone(statement)
      }
    }
  }

  func fileSystemEntryExists(at url: URL) -> Bool {
    if FileManager.default.fileExists(atPath: url.path) {
      return true
    }
    return (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
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
    try Data("unrelated".utf8).write(to: unrelatedCacheURL)
    try FileManager.default.createSymbolicLink(
      at: exactCompanionURLs[0],
      withDestinationURL: directoryURL.appending(path: "missing-journal-target")
    )
    for companionURL in exactCompanionURLs.dropFirst() {
      try Data("old companion".utf8).write(to: companionURL)
    }
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
