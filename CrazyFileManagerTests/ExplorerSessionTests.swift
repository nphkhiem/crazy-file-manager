import Foundation
import Testing

@testable import CrazyFileManager

@MainActor
@Suite("Explorer Session")
struct ExplorerSessionTests {
  @Test
  func
    givenLiteralCachedSnapshot_whenLaunchPreparationCompletes_thenSessionRestoresCompletedResults()
    async throws
  {
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/cached",
      volumeID: "CACHED-HOME"
    )
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let expiresAt = completedAt.addingTimeInterval(86_400)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: scope.location,
      name: "cached",
      kind: .folder,
      diskUsedBytes: 4_096,
      apparentSizeBytes: 4_096,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let item = StorageItemSummary(
      id: UUID(),
      location: scope.location.appending(path: "largest.bin"),
      name: "largest.bin",
      kind: .file,
      diskUsedBytes: 4_096
    )
    let snapshot = CachedScanSnapshot(
      scanID: ScanID(rawValue: UUID()),
      scope: scope,
      completion: ScanCompletion(accessibleItemCount: 1, issueCount: 0),
      completedAt: completedAt,
      expiresAt: expiresAt,
      largestItems: [item],
      treeRoot: root,
      rootPage: StorageTreePage(
        parentID: root.id,
        items: [],
        nextOffset: nil
      )
    )
    let index = InMemoryScanSnapshotIndex()
    await index.enqueueLaunchPreparation(.success(.available(snapshot)))
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: scanner,
      snapshotIndex: index
    )

    await session.waitForLaunchPreparation()

    #expect(session.scanState == .completed(snapshot.completion))
    #expect(session.scopeSelection == .homeFolder)
    #expect(session.selectedScope == scope)
    #expect(session.completedScopeDescription?.availability == .available(scope))
    #expect(session.treeRoot == root)
    #expect(session.treePages[root.id] == snapshot.rootPage)
    #expect(session.largestItems == [item])
    #expect(session.completedAt == completedAt)
    #expect(session.expiresAt == expiresAt)
    #expect(session.cacheNotice == nil)
    #expect(await scanner.requestedScopes.isEmpty)
  }

  @Test
  func givenCompletedScan_whenAnItemIsSelected_thenItsDetailAndCapabilityLoad() async throws {
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      name: "tester",
      kind: .folder,
      diskUsedBytes: 4_096,
      apparentSizeBytes: 4_096,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: URL(filePath: "/Users/tester/Documents", directoryHint: .isDirectory),
      name: "Documents",
      kind: .folder,
      diskUsedBytes: 1_024,
      apparentSizeBytes: 1_024,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }

    session.selectItem(child.id)
    await session.waitForSelectedItemDetail()

    #expect(session.selectedItemDetail?.item.id == child.id)
    #expect(session.selectedItemCapability?.canRename == true)
  }

  @Test
  func givenARestrictedItemSelected_whenDetailLoads_thenCapabilityReflectsTheRestriction()
    async throws
  {
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      name: "tester",
      kind: .folder,
      diskUsedBytes: 4_096,
      apparentSizeBytes: 4_096,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let restrictedChild = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: URL(
        filePath: "/Users/tester/Library/Application Support/App",
        directoryHint: .isDirectory
      ),
      name: "App",
      kind: .folder,
      diskUsedBytes: 10,
      apparentSizeBytes: 10,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [restrictedChild]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }

    session.selectItem(restrictedChild.id)
    await session.waitForSelectedItemDetail()

    #expect(session.selectedItemCapability?.canRename == false)
    #expect(session.selectedItemCapability?.cannotRenameReason == "Managed by another app.")
  }

  @Test
  func givenSelectionCleared_whenSetToNil_thenDetailAndCapabilityClear() async throws {
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      name: "tester",
      kind: .folder,
      diskUsedBytes: 4_096,
      apparentSizeBytes: 4_096,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: URL(filePath: "/Users/tester/Documents", directoryHint: .isDirectory),
      name: "Documents",
      kind: .folder,
      diskUsedBytes: 1_024,
      apparentSizeBytes: 1_024,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    session.selectItem(child.id)
    await session.waitForSelectedItemDetail()

    session.selectItem(nil)

    #expect(session.selectedItemDetail == nil)
    #expect(session.selectedItemCapability == nil)
  }

  @Test
  func givenItemDetailQueryFails_whenSelected_thenDetailAndCapabilityStayNilRatherThanStale()
    async throws
  {
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      name: "tester",
      kind: .folder,
      diskUsedBytes: 4_096,
      apparentSizeBytes: 4_096,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: URL(filePath: "/Users/tester/Documents", directoryHint: .isDirectory),
      name: "Documents",
      kind: .folder,
      diskUsedBytes: 1_024,
      apparentSizeBytes: 1_024,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    await index.failNextItemDetail()

    session.selectItem(child.id)
    await session.waitForSelectedItemDetail()

    #expect(session.selectedItemDetail == nil)
    #expect(session.selectedItemCapability == nil)
  }

  @Test
  func givenLargestItemsShown_whenARowIsSelected_thenSelectedItemIDUpdates() async throws {
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/cached",
      volumeID: "CACHED-HOME"
    )
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: scope.location,
      name: "cached",
      kind: .folder,
      diskUsedBytes: 4_096,
      apparentSizeBytes: 4_096,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let item = StorageItemSummary(
      id: UUID(),
      location: scope.location.appending(path: "largest.bin"),
      name: "largest.bin",
      kind: .file,
      diskUsedBytes: 4_096
    )
    let snapshot = CachedScanSnapshot(
      scanID: ScanID(rawValue: UUID()),
      scope: scope,
      completion: ScanCompletion(accessibleItemCount: 1, issueCount: 0),
      completedAt: completedAt,
      expiresAt: completedAt.addingTimeInterval(86_400),
      largestItems: [item],
      treeRoot: root,
      rootPage: StorageTreePage(parentID: root.id, items: [], nextOffset: nil)
    )
    let index = InMemoryScanSnapshotIndex()
    await index.enqueueLaunchPreparation(.success(.available(snapshot)))
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: ControlledFileSystemScanner(),
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()

    session.selectItem(item.id)

    #expect(session.selectedItemID == item.id)
  }

  @Test
  func
    givenAnEligibleSelectedItem_whenRenameBeginsAndAnInvalidNameIsProposed_thenValidationMessageAppears()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "report.pdf")
    try Data("hello".utf8).write(to: fileURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 4_096,
      apparentSizeBytes: 4_096,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: fileURL,
      name: "report.pdf",
      kind: .file,
      diskUsedBytes: 10,
      apparentSizeBytes: 10,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    session.selectItem(child.id)
    await session.waitForSelectedItemDetail()

    await session.beginRename(child.id)
    session.updateRenameProposal("")

    #expect(session.renamingItemID == child.id)
    #expect(session.renameValidationMessage != nil)
  }

  @Test
  func
    givenAnUnselectedEligibleRow_whenSelectedAndRenameBeginsWithoutAwaitingDetailInBetween_thenRenamingStillBeginsCorrectly()
    async throws
  {
    // Mirrors a real double-click on a previously-unselected row: selection
    // and beginRename fire back to back, racing the async detail load that
    // selection kicks off. beginRename must wait for that load internally
    // rather than silently no-op because selectedItemDetail hasn't caught up.
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: fileURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }

    session.selectItem(child.id)
    await session.beginRename(child.id)

    #expect(session.renamingItemID == child.id)
  }

  @Test
  func
    givenAValidRenameProposal_whenCommitted_thenTheItemPersistsUnderTheNewNameAndRenamingStateClears()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let originalURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: originalURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: originalURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    session.selectItem(child.id)
    await session.waitForSelectedItemDetail()
    await session.beginRename(child.id)
    session.updateRenameProposal("renamed.txt")

    let succeeded = await session.commitRename()

    #expect(succeeded)
    #expect(session.renamingItemID == nil)
    #expect(session.lastRename?.oldName == "note.txt")
    #expect(session.lastRename?.newName == "renamed.txt")
    #expect(!FileManager.default.fileExists(atPath: originalURL.path(percentEncoded: false)))
    #expect(
      FileManager.default.fileExists(
        atPath: directory.appending(path: "renamed.txt").path(percentEncoded: false)
      )
    )
  }

  @Test
  func
    givenALoadedFolderWithAChild_whenTheFolderIsRenamed_thenTheChildsCachedLocationReflectsTheNewFolderName()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let documentsURL = directory.appending(path: "documents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: documentsURL,
      withIntermediateDirectories: true
    )
    let reportURL = documentsURL.appending(path: "report.pdf")
    try Data("hello".utf8).write(to: reportURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let documentsFolder = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: documentsURL,
      name: "documents",
      kind: .folder,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: false
    )
    let reportItem = StorageTreeItem(
      id: UUID(),
      parentID: documentsFolder.id,
      location: reportURL,
      name: "report.pdf",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [documentsFolder], documentsFolder.id: [reportItem]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    session.setTreeItem(documentsFolder.id, expanded: true)
    await eventually {
      session.treePages[documentsFolder.id]?.items.count == 1
    }
    session.selectItem(documentsFolder.id)
    await session.waitForSelectedItemDetail()
    await session.beginRename(documentsFolder.id)
    session.updateRenameProposal("archive")

    let succeeded = await session.commitRename()

    #expect(succeeded)
    let expectedReportPath =
      directory
      .appending(path: "archive/report.pdf", directoryHint: .notDirectory)
      .path(percentEncoded: false)
    #expect(
      session.treePages[documentsFolder.id]?.items.first?.location.path(percentEncoded: false)
        == expectedReportPath
    )
  }

  @Test
  func
    givenTheTargetIsReplacedDuringTheEditingWindow_whenCommitted_thenItRejectsRatherThanRenamingTheReplacement()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let originalURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: originalURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: originalURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    session.selectItem(child.id)
    await session.waitForSelectedItemDetail()
    await session.beginRename(child.id)

    // Simulate another process replacing the file with different content
    // during the (potentially long) editing window, before the user commits.
    try FileManager.default.removeItem(at: originalURL)
    try Data("replaced by someone else".utf8).write(to: originalURL)

    session.updateRenameProposal("renamed.txt")
    let succeeded = await session.commitRename()

    #expect(!succeeded)
    #expect(session.renameValidationMessage != nil)
    #expect(FileManager.default.fileExists(atPath: originalURL.path(percentEncoded: false)))
    #expect(
      !FileManager.default.fileExists(
        atPath: directory.appending(path: "renamed.txt").path(percentEncoded: false)
      )
    )
  }

  @Test
  func givenAnExtensionChangingProposal_whenCommitted_thenItPausesForConfirmationWithoutMutating()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let originalURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: originalURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: originalURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    session.selectItem(child.id)
    await session.waitForSelectedItemDetail()
    await session.beginRename(child.id)
    session.updateRenameProposal("note.pdf")

    let firstAttempt = await session.commitRename()

    #expect(!firstAttempt)
    #expect(session.pendingRenameExtensionConfirmation != nil)
    #expect(FileManager.default.fileExists(atPath: originalURL.path(percentEncoded: false)))

    let confirmed = await session.confirmRenameExtensionChange()

    #expect(confirmed)
    #expect(session.pendingRenameExtensionConfirmation == nil)
    #expect(!FileManager.default.fileExists(atPath: originalURL.path(percentEncoded: false)))
    #expect(
      FileManager.default.fileExists(
        atPath: directory.appending(path: "note.pdf").path(percentEncoded: false)
      )
    )
  }

  @Test
  func givenAPendingExtensionConfirmation_whenDismissed_thenTheItemRemainsInEditStateUnchanged()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let originalURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: originalURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: originalURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    session.selectItem(child.id)
    await session.waitForSelectedItemDetail()
    await session.beginRename(child.id)
    session.updateRenameProposal("note.pdf")
    _ = await session.commitRename()

    session.dismissRenameExtensionConfirmation()

    #expect(session.pendingRenameExtensionConfirmation == nil)
    #expect(session.renamingItemID == child.id)
    #expect(FileManager.default.fileExists(atPath: originalURL.path(percentEncoded: false)))
  }

  @Test
  func givenASuccessfulRename_whenUndone_thenTheOriginalNameIsRestoredAndLastRenameClears()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let originalURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: originalURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: originalURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    session.selectItem(child.id)
    await session.waitForSelectedItemDetail()
    await session.beginRename(child.id)
    session.updateRenameProposal("renamed.txt")
    _ = await session.commitRename()

    let undone = await session.undoLastRename()

    #expect(undone)
    #expect(session.lastRename == nil)
    #expect(
      FileManager.default.fileExists(atPath: originalURL.path(percentEncoded: false))
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: directory.appending(path: "renamed.txt").path(percentEncoded: false)
      )
    )
  }

  @Test
  func givenARenamedItemDeletedBeforeUndoRuns_whenUndone_thenItFailsClosedAndClearsLastRename()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let originalURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: originalURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: originalURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    session.selectItem(child.id)
    await session.waitForSelectedItemDetail()
    await session.beginRename(child.id)
    session.updateRenameProposal("renamed.txt")
    _ = await session.commitRename()
    try FileManager.default.removeItem(
      at: directory.appending(path: "renamed.txt")
    )

    let undone = await session.undoLastRename()

    #expect(!undone)
    #expect(session.lastRename == nil)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  @Test
  func
    givenExpiredCachedSnapshot_whenLaunchPreparationCompletes_thenResultsClearAndPreviousScopeIsSelected()
    async throws
  {
    let scope = ScanScope.testScope(
      kind: .entireInternalDisk,
      path: "/",
      volumeID: "INTERNAL"
    )
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-07-31T10:00:00Z")
    )
    let index = InMemoryScanSnapshotIndex()
    await index.enqueueLaunchPreparation(
      .success(.expired(previousScope: scope, completedAt: completedAt))
    )
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: ControlledFileSystemScanner(),
      snapshotIndex: index
    )

    await session.waitForLaunchPreparation()

    #expect(session.scanState == .idle)
    #expect(session.selectedScope == scope)
    #expect(session.scopeSelection == .entireInternalDisk)
    #expect(session.treeRoot == nil)
    #expect(session.largestItems.isEmpty)
    #expect(session.cacheNotice == .expired)
    #expect(!session.cacheNotice!.message.contains("/"))
  }

  @Test
  func
    givenCleanupFailure_whenLaunchPreparationCompletes_thenStaleResultsStayEmptyWithPathFreeNotice()
    async throws
  {
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/cached",
      volumeID: "CACHED-HOME"
    )
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-07-31T10:00:00Z")
    )
    let index = InMemoryScanSnapshotIndex()
    await index.enqueueLaunchPreparation(
      .success(.cleanupFailed(previousScope: scope, completedAt: completedAt))
    )
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: ControlledFileSystemScanner(),
      snapshotIndex: index
    )

    await session.waitForLaunchPreparation()

    #expect(session.scanState == .idle)
    #expect(session.selectedScope == scope)
    #expect(session.treeRoot == nil)
    #expect(session.largestItems.isEmpty)
    #expect(session.cacheNotice == .cleanupFailed)
    #expect(!session.cacheNotice!.message.contains("/"))
  }

  @Test
  func givenReconstructedCache_whenLaunchPreparationCompletes_thenWelcomeStateHasPathFreeNotice()
    async
  {
    let index = InMemoryScanSnapshotIndex()
    await index.enqueueLaunchPreparation(.success(.reconstructed))
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: ControlledFileSystemScanner(),
      snapshotIndex: index
    )

    await session.waitForLaunchPreparation()

    #expect(session.scanState == .idle)
    #expect(session.treeRoot == nil)
    #expect(session.largestItems.isEmpty)
    #expect(session.cacheNotice == .reconstructed)
    #expect(!session.cacheNotice!.message.contains("/"))
  }

  @Test
  func givenRestoredSnapshot_whenScanDataIsCleared_thenCompletedProvenanceClearsWithoutScanning()
    async throws
  {
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/cached",
      volumeID: "CACHED-HOME"
    )
    let snapshot = try cachedSnapshot(scope: scope)
    let index = InMemoryScanSnapshotIndex()
    await index.enqueueLaunchPreparation(.success(.available(snapshot)))
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()

    #expect(await session.clearScanData())

    #expect(session.scanState == .idle)
    #expect(session.selectedScope == scope)
    #expect(session.completedScopeDescription == nil)
    #expect(session.completedAt == nil)
    #expect(session.expiresAt == nil)
    #expect(session.treeRoot == nil)
    #expect(session.largestItems.isEmpty)
    #expect(await scanner.requestedScopes.isEmpty)
  }

  @Test
  func
    givenRestoredSnapshot_whenClearingScanDataFails_thenCompletedResultsRemainWithPathFreeNotice()
    async throws
  {
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/cached",
      volumeID: "CACHED-HOME"
    )
    let snapshot = try cachedSnapshot(scope: scope)
    let index = InMemoryScanSnapshotIndex()
    await index.enqueueLaunchPreparation(.success(.available(snapshot)))
    await index.failNextClearCompletedSnapshot()
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: ControlledFileSystemScanner(),
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()

    #expect(!(await session.clearScanData()))

    #expect(session.scanState == .completed(snapshot.completion))
    #expect(session.completedScopeDescription?.availability == .available(scope))
    #expect(session.treeRoot == snapshot.treeRoot)
    #expect(session.cacheNotice == .cleanupFailed)
    #expect(!session.cacheNotice!.message.contains("/"))
  }

  @Test
  func
    givenRestoredSnapshotWithFailedClear_whenSameScanRefreshSucceeds_thenCleanupNoticeAndNavigationRemain()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let dateProvider = MutableExplorerDateProvider(
      now: completedAt.addingTimeInterval(1)
    )
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/cached",
      volumeID: "CACHED-HOME"
    )
    let snapshot = try cachedSnapshot(
      scope: scope,
      completedAt: completedAt
    )
    let index = InMemoryScanSnapshotIndex(dateProvider: dateProvider)
    await index.enqueueLaunchPreparation(.success(.available(snapshot)))
    await index.failNextClearCompletedSnapshot()
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: ControlledFileSystemScanner(),
      snapshotIndex: index,
      dateProvider: dateProvider
    )
    await session.waitForLaunchPreparation()
    session.selectItem(snapshot.treeRoot.id)
    let treePages = session.treePages
    let expandedIDs = session.expandedTreeItemIDs
    let completedScopeDescription = session.completedScopeDescription
    let completedAtPresentation = session.completedAt
    let expiresAtPresentation = session.expiresAt
    let scanState = session.scanState

    #expect(!(await session.clearScanData()))
    #expect(session.treeRoot == snapshot.treeRoot)
    #expect(session.treePages == treePages)
    #expect(session.expandedTreeItemIDs == expandedIDs)
    #expect(session.selectedItemID == snapshot.treeRoot.id)
    #expect(session.completedScopeDescription == completedScopeDescription)
    #expect(session.completedAt == completedAtPresentation)
    #expect(session.expiresAt == expiresAtPresentation)
    #expect(session.scanState == scanState)
    #expect(session.cacheNotice == .cleanupFailed)

    await index.enqueueRefreshPreparation(.success(.available(snapshot)))
    await session.refreshCacheLifecycle()

    #expect(session.treeRoot == snapshot.treeRoot)
    #expect(session.treePages == treePages)
    #expect(session.expandedTreeItemIDs == expandedIDs)
    #expect(session.selectedItemID == snapshot.treeRoot.id)
    #expect(session.completedScopeDescription == completedScopeDescription)
    #expect(session.completedAt == completedAtPresentation)
    #expect(session.expiresAt == expiresAtPresentation)
    #expect(session.scanState == scanState)
    #expect(session.cacheNotice == .cleanupFailed)
  }

  @Test
  func givenRestoredSnapshot_whenRefreshOccursAtExpiryBoundary_thenResultsClearOnlyAtBoundary()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let dateProvider = MutableExplorerDateProvider(now: completedAt)
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/cached",
      volumeID: "CACHED-HOME"
    )
    let snapshot = try cachedSnapshot(
      scope: scope,
      completedAt: completedAt
    )
    let index = InMemoryScanSnapshotIndex(dateProvider: dateProvider)
    await index.enqueueLaunchPreparation(.success(.available(snapshot)))
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: ControlledFileSystemScanner(),
      snapshotIndex: index,
      dateProvider: dateProvider
    )
    await session.waitForLaunchPreparation()

    dateProvider.advance(to: snapshot.expiresAt.addingTimeInterval(-0.001))
    await index.enqueueRefreshPreparation(.success(.available(snapshot)))
    await session.refreshCacheLifecycle()
    #expect(session.treeRoot == snapshot.treeRoot)

    dateProvider.advance(to: snapshot.expiresAt)
    await index.enqueueRefreshPreparation(
      .success(
        .expired(
          previousScope: scope,
          completedAt: snapshot.completedAt
        )
      )
    )
    await session.refreshCacheLifecycle()

    #expect(session.scanState == .idle)
    #expect(session.treeRoot == nil)
    #expect(session.largestItems.isEmpty)
    #expect(session.cacheNotice == .expired)
  }

  @Test
  func
    givenLoadedTreeNavigation_whenSameCachedScanRefreshes_thenPagesDisclosureSelectionProvenanceAndStateRemainStable()
    async throws
  {
    let harness = ExplorerSessionHarness(
      rootChildCount: 201,
      folderChildCount: 1
    )
    await harness.completeScan()
    let root = try #require(harness.session.treeRoot)
    let folderID = try #require(harness.nestedFolderID)
    await harness.session.loadNextTreePage(for: root.id)
    harness.session.setTreeItem(folderID, expanded: true)
    await eventually {
      harness.session.treePages[folderID]?.items.count == 1
    }
    let selectedID = try #require(
      harness.session.treePages[folderID]?.items.first?.id
    )
    harness.session.selectItem(selectedID)
    let pages = harness.session.treePages
    let expandedIDs = harness.session.expandedTreeItemIDs
    let completedScopeDescription = harness.session.completedScopeDescription
    let completedAt = harness.session.completedAt
    let expiresAt = harness.session.expiresAt
    let scanState = harness.session.scanState
    let snapshot = try await harness.index.cachedSnapshot()
    await harness.index.enqueueRefreshPreparation(.success(.available(snapshot)))

    await harness.session.refreshCacheLifecycle()

    #expect(harness.session.treePages == pages)
    #expect(harness.session.expandedTreeItemIDs == expandedIDs)
    #expect(harness.session.selectedItemID == selectedID)
    #expect(harness.session.completedScopeDescription == completedScopeDescription)
    #expect(harness.session.completedAt == completedAt)
    #expect(harness.session.expiresAt == expiresAt)
    #expect(harness.session.scanState == scanState)
    #expect(harness.session.cacheNotice == nil)
  }

  @Test
  func
    givenValidRestoredSnapshot_whenRefreshFailsBeforeExpiry_thenResultsAndProvenanceRemainWithPathFreeNotice()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let dateProvider = MutableExplorerDateProvider(
      now: completedAt.addingTimeInterval(1)
    )
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/cached",
      volumeID: "CACHED-HOME"
    )
    let snapshot = try cachedSnapshot(
      scope: scope,
      completedAt: completedAt
    )
    let index = InMemoryScanSnapshotIndex(dateProvider: dateProvider)
    await index.enqueueLaunchPreparation(.success(.available(snapshot)))
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: ControlledFileSystemScanner(),
      snapshotIndex: index,
      dateProvider: dateProvider
    )
    await session.waitForLaunchPreparation()
    await index.enqueueRefreshPreparation(
      .failure(.statementFailed(code: 5))
    )

    await session.refreshCacheLifecycle()

    #expect(session.scanState == .completed(snapshot.completion))
    #expect(session.treeRoot == snapshot.treeRoot)
    #expect(session.largestItems == snapshot.largestItems)
    #expect(session.completedScopeDescription?.availability == .available(scope))
    #expect(session.completedAt == snapshot.completedAt)
    #expect(session.expiresAt == snapshot.expiresAt)
    #expect(
      session.cacheNotice?.message
        == "Saved scan data couldn’t be checked. Try again."
    )
    #expect(!(session.cacheNotice?.message.contains("/") ?? true))
  }

  @Test
  func
    givenRestoredSnapshotAtKnownExpiry_whenRefreshFails_thenStaleResultsAndProvenanceClearWithPathFreeCleanupNotice()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let dateProvider = MutableExplorerDateProvider(now: completedAt)
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/cached",
      volumeID: "CACHED-HOME"
    )
    let snapshot = try cachedSnapshot(
      scope: scope,
      completedAt: completedAt
    )
    let index = InMemoryScanSnapshotIndex(dateProvider: dateProvider)
    await index.enqueueLaunchPreparation(.success(.available(snapshot)))
    let session = ExplorerSession(
      homeDirectoryURL: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
      scanner: ControlledFileSystemScanner(),
      snapshotIndex: index,
      dateProvider: dateProvider
    )
    await session.waitForLaunchPreparation()
    dateProvider.advance(to: snapshot.expiresAt)
    await index.enqueueRefreshPreparation(
      .failure(.statementFailed(code: 5))
    )

    await session.refreshCacheLifecycle()

    #expect(session.scanState == .idle)
    #expect(session.treeRoot == nil)
    #expect(session.largestItems.isEmpty)
    #expect(session.completedScopeDescription == nil)
    #expect(session.completedAt == nil)
    #expect(session.expiresAt == nil)
    #expect(session.cacheNotice == .cleanupFailed)
    #expect(!(session.cacheNotice?.message.contains("/") ?? true))
  }

  @Test
  func
    givenActiveHomeScanAtCachedExpiry_whenRefreshFails_thenActiveStateAndScopeRemainWhileStaleResultsClear()
    async throws
  {
    let completedAt = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let dateProvider = MutableExplorerDateProvider(now: completedAt)
    let home = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/tester",
      volumeID: "HOME"
    )
    let cachedScope = ScanScope.testScope(
      kind: .entireInternalDisk,
      path: "/",
      volumeID: "INTERNAL"
    )
    let snapshot = try cachedSnapshot(
      scope: cachedScope,
      completedAt: completedAt
    )
    let index = InMemoryScanSnapshotIndex(dateProvider: dateProvider)
    await index.enqueueLaunchPreparation(.success(.available(snapshot)))
    let scanner = ControlledFileSystemScanner()
    let authorizer = ControlledScanScopeAuthorizer(
      descriptions: [
        ScanScopeDescription(
          selection: .homeFolder,
          availability: .available(home)
        ),
        ScanScopeDescription(
          selection: .entireInternalDisk,
          availability: .available(cachedScope)
        ),
      ]
    )
    let session = ExplorerSession(
      homeDirectoryURL: home.location,
      scanner: scanner,
      snapshotIndex: index,
      scopeAuthorizer: authorizer,
      dateProvider: dateProvider
    )
    await session.waitForLaunchPreparation()
    #expect(session.selectHomeFolder())
    #expect(session.startScan())
    await eventually {
      await scanner.requestedScopes == [home]
    }
    dateProvider.advance(to: snapshot.expiresAt)
    await index.enqueueRefreshPreparation(
      .failure(.statementFailed(code: 5))
    )

    await session.refreshCacheLifecycle()

    #expect(session.scanState == .scanning(.initial))
    #expect(session.selectedScope == home)
    #expect(session.scopeSelection == .homeFolder)
    #expect(session.scopeDescription.availability == .available(home))
    #expect(session.treeRoot == nil)
    #expect(session.completedScopeDescription == nil)
    #expect(session.completedAt == nil)
    #expect(session.expiresAt == nil)
    #expect(session.cacheNotice == .cleanupFailed)
    #expect(await session.cancelScan())
  }

  @Test
  func
    givenDelayedCachedRestoration_whenScanStarts_thenActiveScopeRemainsAndPromotionReplacesCache()
    async throws
  {
    let cachedScope = ScanScope.testScope(
      kind: .entireInternalDisk,
      path: "/",
      volumeID: "CACHED-INTERNAL"
    )
    let snapshot = try cachedSnapshot(scope: cachedScope)
    let index = InMemoryScanSnapshotIndex()
    await index.enqueueLaunchPreparation(.success(.available(snapshot)))
    await index.blockNextLaunchPreparation()
    let homeDirectoryURL = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: homeDirectoryURL,
      scanner: scanner,
      snapshotIndex: index
    )
    await eventually {
      await index.isLaunchPreparationBlocked
    }

    #expect(session.startScan())
    #expect(session.scanState == .scanning(.initial))
    await index.unblockLaunchPreparation()
    await eventually {
      session.treeRoot == snapshot.treeRoot
    }

    #expect(session.scanState == .scanning(.initial))
    #expect(session.selectedScope == .homeFolder(homeDirectoryURL))
    #expect(session.scopeSelection == .homeFolder)
    #expect(session.completedScopeDescription?.availability == .available(cachedScope))
    await eventually {
      await scanner.requestedScopes == [.homeFolder(homeDirectoryURL)]
    }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState {
        return true
      }
      return false
    }

    #expect(
      session.completedScopeDescription?.availability
        == .available(.homeFolder(homeDirectoryURL))
    )
  }

  @Test
  func givenInMemoryIndexWithInjectedClock_whenCandidatePromotes_thenExpiryIsCompletionDerived()
    async throws
  {
    let completionDate = try #require(
      ISO8601DateFormatter().date(from: "2026-08-01T10:00:00Z")
    )
    let index = InMemoryScanSnapshotIndex(
      dateProvider: FixedDateProvider(now: completionDate)
    )
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/tester",
      volumeID: "HOME"
    )
    let candidate = try await index.beginCandidate(for: scope)

    let snapshot = try await index.promoteCandidate(
      candidate,
      expectedItemCount: 0,
      expectedIssueCount: 0
    )

    #expect(snapshot.completedAt == completionDate)
    #expect(snapshot.expiresAt == completionDate.addingTimeInterval(86_400))
  }

  @Test
  func givenApprovedCustomLocation_whenSessionStoresIt_thenResolvedCustomScopeIsSelected()
    throws
  {
    let location = URL(
      filePath: "/Volumes/Archive",
      directoryHint: .isDirectory
    )
    let reference = CustomScopeReference(
      displayName: "Archive",
      lastKnownLocation: location
    )
    let custom = ScanScope.testScope(
      kind: .custom,
      path: "/Volumes/Archive",
      volumeID: "ARCHIVE"
    )
    let bookmarkStore = ControlledCustomScopeBookmarkStore(
      reference: reference
    )
    let authorizer = ControlledScanScopeAuthorizer(
      descriptions: [
        ScanScopeDescription(
          selection: .homeFolder,
          availability: .available(
            ScanScope.testScope(
              kind: .homeFolder,
              path: "/Users/tester",
              volumeID: "HOME"
            )
          )
        ),
        ScanScopeDescription(
          selection: .custom(reference),
          availability: .available(custom)
        ),
      ]
    )
    let harness = ExplorerSessionHarness(
      scopeAuthorizer: authorizer,
      customScopeBookmarkStore: bookmarkStore
    )

    #expect(harness.session.approveCustomScope(location))

    #expect(bookmarkStore.approvedLocations == [location])
    #expect(harness.session.scopeSelection == .custom(reference))
    #expect(harness.session.selectedScope == custom)
  }

  @Test
  func givenCustomAccessCannotBeSaved_whenLocationIsApproved_thenSelectionAndPathStayPrivate() {
    let bookmarkStore = ControlledCustomScopeBookmarkStore(
      error: ControlledBookmarkError.failed
    )
    let harness = ExplorerSessionHarness(
      customScopeBookmarkStore: bookmarkStore
    )

    #expect(
      !harness.session.approveCustomScope(
        URL(filePath: "/private/example", directoryHint: .isDirectory)
      )
    )

    #expect(harness.session.scopeSelection == .homeFolder)
    #expect(
      harness.session.scopeFailureMessage
        == "The selected location could not be saved."
    )
  }

  @Test
  func givenFullDiskGuidance_whenNotNowIsChosen_thenDismissalLastsForSession() {
    let harness = ExplorerSessionHarness()

    harness.session.dismissFullDiskAccessGuidance()

    #expect(harness.session.isFullDiskAccessGuidanceDismissed)
    #expect(harness.session.selectEntireInternalDisk())
    #expect(harness.session.isFullDiskAccessGuidanceDismissed)
  }

  @Test
  func givenThreeAvailableScopes_whenSelectionChanges_thenSessionPublishesResolvedScope()
    throws
  {
    let home = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/tester",
      volumeID: "HOME"
    )
    let disk = ScanScope.testScope(
      kind: .entireInternalDisk,
      path: "/",
      volumeID: "INTERNAL"
    )
    let custom = ScanScope.testScope(
      kind: .custom,
      path: "/Volumes/Archive",
      volumeID: "ARCHIVE"
    )
    let reference = CustomScopeReference(
      displayName: "Archive",
      lastKnownLocation: custom.location
    )
    let authorizer = ControlledScanScopeAuthorizer(
      descriptions: [
        ScanScopeDescription(
          selection: .homeFolder,
          availability: .available(home)
        ),
        ScanScopeDescription(
          selection: .entireInternalDisk,
          availability: .available(disk)
        ),
        ScanScopeDescription(
          selection: .custom(reference),
          availability: .available(custom)
        ),
      ]
    )
    let harness = ExplorerSessionHarness(scopeAuthorizer: authorizer)

    #expect(harness.session.scopeSelection == .homeFolder)
    #expect(harness.session.scopeDescription.availability == .available(home))
    #expect(harness.session.selectEntireInternalDisk())
    #expect(harness.session.scopeSelection == .entireInternalDisk)
    #expect(harness.session.selectedScope == disk)
    #expect(harness.session.selectCustomScope(reference))
    #expect(harness.session.scopeSelection == .custom(reference))
    #expect(harness.session.selectedScope == custom)
    #expect(harness.session.selectHomeFolder())
    #expect(harness.session.selectedScope == home)
  }

  @Test
  func givenScopeIdentityChangesBeforeScan_whenScanStarts_thenPreparedScopeIsCaptured()
    async
  {
    let describedScope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/tester",
      volumeID: "OLD-VOLUME"
    )
    let preparedScope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/tester",
      volumeID: "CURRENT-VOLUME"
    )
    let authorizer = ControlledScanScopeAuthorizer(
      descriptions: [
        ScanScopeDescription(
          selection: .homeFolder,
          availability: .available(describedScope)
        )
      ]
    )
    authorizer.setPreparedScope(preparedScope, for: .homeFolder)
    let harness = ExplorerSessionHarness(scopeAuthorizer: authorizer)

    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }

    #expect(await harness.scanner.requestedScopes == [preparedScope])
    #expect(await harness.index.requestedScopes == [preparedScope])
    await harness.scanner.finish()
    await eventually {
      if case .completed = harness.session.scanState {
        return true
      }
      return false
    }
  }

  @Test
  func givenPreparedScope_whenScanCompletes_thenAccessLeaseIsReleasedOnce()
    async
  {
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/tester",
      volumeID: "HOME"
    )
    let authorizer = ControlledScanScopeAuthorizer(
      descriptions: [
        ScanScopeDescription(
          selection: .homeFolder,
          availability: .available(scope)
        )
      ]
    )
    let harness = ExplorerSessionHarness(scopeAuthorizer: authorizer)

    await harness.completeScan()

    #expect(authorizer.finishedLeaseCount == 1)
  }

  @Test
  func givenPreparedScope_whenScanIsCancelled_thenAccessLeaseIsReleasedOnce()
    async
  {
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/tester",
      volumeID: "HOME"
    )
    let authorizer = ControlledScanScopeAuthorizer(
      descriptions: [
        ScanScopeDescription(
          selection: .homeFolder,
          availability: .available(scope)
        )
      ]
    )
    let harness = ExplorerSessionHarness(scopeAuthorizer: authorizer)
    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }

    #expect(await harness.session.cancelScan())

    #expect(authorizer.finishedLeaseCount == 1)
  }

  @Test
  func givenPreparedScope_whenScanFails_thenAccessLeaseIsReleasedOnce()
    async
  {
    let scope = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/tester",
      volumeID: "HOME"
    )
    let authorizer = ControlledScanScopeAuthorizer(
      descriptions: [
        ScanScopeDescription(
          selection: .homeFolder,
          availability: .available(scope)
        )
      ]
    )
    let harness = ExplorerSessionHarness(scopeAuthorizer: authorizer)
    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }

    await harness.scanner.fail(ControlledScanError.failed)
    await eventually {
      if case .failed = harness.session.scanState {
        return true
      }
      return false
    }

    #expect(authorizer.finishedLeaseCount == 1)
  }

  @Test
  func
    givenCompletedResultsAndDisconnectedSelection_whenScanStarts_thenResultsRemainWithPathFreeFailure()
    async
  {
    let home = ScanScope.testScope(
      kind: .homeFolder,
      path: "/Users/tester",
      volumeID: "HOME"
    )
    let disconnectedLocation = URL(
      filePath: "/Volumes/Offline",
      directoryHint: .isDirectory
    )
    let reference = CustomScopeReference(
      displayName: "Offline",
      lastKnownLocation: disconnectedLocation
    )
    let authorizer = ControlledScanScopeAuthorizer(
      descriptions: [
        ScanScopeDescription(
          selection: .homeFolder,
          availability: .available(home)
        ),
        ScanScopeDescription(
          selection: .custom(reference),
          availability: .disconnected(
            lastKnownLocation: disconnectedLocation
          )
        ),
      ]
    )
    let harness = ExplorerSessionHarness(scopeAuthorizer: authorizer)
    await harness.completeScan()
    let completedRoot = harness.session.treeRoot
    let completedScopeDescription = harness.session.scopeDescription

    #expect(harness.session.selectCustomScope(reference))
    #expect(!harness.session.startScan())

    #expect(harness.session.treeRoot == completedRoot)
    #expect(
      harness.session.completedScopeDescription
        == completedScopeDescription
    )
    #expect(
      harness.session.scopeDescription.selection
        == .custom(reference)
    )
    #expect(
      harness.session.scopeFailureMessage
        == "The selected location is no longer available."
    )
    #expect(!harness.session.scopeFailureMessage!.contains("/Volumes"))
  }

  @Test
  func givenUnsupportedSelection_whenScanStarts_thenScanIsRejectedWithPathFreeFailure() {
    let unsupportedLocation = URL(
      filePath: "/Volumes/Unsupported",
      directoryHint: .isDirectory
    )
    let reference = CustomScopeReference(
      displayName: "Unsupported",
      lastKnownLocation: unsupportedLocation
    )
    let authorizer = ControlledScanScopeAuthorizer(
      descriptions: [
        ScanScopeDescription(
          selection: .homeFolder,
          availability: .available(
            ScanScope.testScope(
              kind: .homeFolder,
              path: "/Users/tester",
              volumeID: "HOME"
            )
          )
        ),
        ScanScopeDescription(
          selection: .custom(reference),
          availability: .unsupported(location: unsupportedLocation)
        ),
      ]
    )
    let harness = ExplorerSessionHarness(scopeAuthorizer: authorizer)

    #expect(harness.session.selectCustomScope(reference))
    #expect(!harness.session.startScan())

    #expect(
      harness.session.scopeFailureMessage
        == "The selected volume isn’t supported."
    )
    #expect(!harness.session.scopeFailureMessage!.contains("/Volumes"))
    #expect(harness.session.scanState == .idle)
  }

  @Test
  func givenAccessRevocationAfterAccessibleBatch_whenScanFinishes_thenPartialResultsRemainUsable()
    async
  {
    let harness = ExplorerSessionHarness()
    let accessibleBatch = harness.batch(
      namesAndSizes: [("accessible.bin", 8_192)]
    )
    let revokedLocation = harness.homeDirectoryURL.appending(
      path: "revoked",
      directoryHint: .isDirectory
    )
    let revokedBatch = FileSystemScanBatch(
      items: [],
      issues: [
        ScanIssue(
          location: revokedLocation,
          kind: .accessDenied,
          message: "The item could not be accessed."
        )
      ],
      progress: ScanProgress(
        discoveredItemCount: 1,
        issueCount: 1,
        currentArea: revokedLocation
      )
    )
    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }

    await harness.scanner.yield(accessibleBatch)
    await harness.scanner.yield(revokedBatch)
    await harness.scanner.finish()
    await eventually {
      harness.session.scanState
        == .completed(
          ScanCompletion(accessibleItemCount: 1, issueCount: 1)
        )
    }

    #expect(harness.session.largestItems.map(\.name) == ["accessible.bin"])
  }

  @Test
  func givenRootVolumeIsRemoved_whenScannerFails_thenSessionPublishesPathFreeFailure()
    async
  {
    let harness = ExplorerSessionHarness()
    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }

    await harness.scanner.fail(FileSystemScanError.scopeUnavailable)
    await eventually {
      if case .failed = harness.session.scanState {
        return true
      }
      return false
    }

    guard case .failed(let failure) = harness.session.scanState else {
      Issue.record("Expected a failed scan")
      return
    }
    #expect(failure.message == "The scan couldn’t be completed.")
    #expect(!failure.message.contains("/"))
  }

  @Test
  func
    givenCompletedResultsAndRootVolumeDrift_whenReplacementFails_thenPreviousBoundaryRemainsUsable()
    async
  {
    let harness = ExplorerSessionHarness(rootChildCount: 1)
    await harness.completeScan()
    let completedRoot = harness.session.treeRoot
    let completedDescription = harness.session.completedScopeDescription
    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 2
    }

    await harness.scanner.fail(FileSystemScanError.scopeChanged)
    await eventually {
      if case .failed = harness.session.scanState {
        return true
      }
      return false
    }

    #expect(harness.session.treeRoot == completedRoot)
    #expect(
      harness.session.completedScopeDescription
        == completedDescription
    )
  }

  @Test
  func givenHomeFolderURL_whenSessionIsCreated_thenSelectsProvidedHomeFolder() {
    let harness = ExplorerSessionHarness()

    #expect(
      harness.session.selectedScope == .homeFolder(harness.homeDirectoryURL)
    )
  }

  @Test
  func givenNewSession_whenNoScanIsRequested_thenScanStateRemainsIdle() {
    let harness = ExplorerSessionHarness()

    #expect(harness.session.scanState == .idle)
  }

  @Test
  func givenIdleSession_whenScanIntentOccursTwice_thenOnlyFirstIntentStarts()
    async
  {
    let harness = ExplorerSessionHarness()

    let firstIntentStarted = harness.session.startScan()
    let secondIntentStarted = harness.session.startScan()
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }

    #expect(firstIntentStarted)
    #expect(!secondIntentStarted)
    #expect(harness.session.scanState == .scanning(.initial))
    #expect(
      await harness.scanner.requestedScopes == [
        .homeFolder(harness.homeDirectoryURL)
      ]
    )
    await harness.scanner.finish()
  }

  @Test
  func givenActiveScan_whenFirstBatchArrives_thenLargestItemsAppearBeforeCompletion()
    async
  {
    let harness = ExplorerSessionHarness()
    let batch = harness.batch(
      namesAndSizes: [
        ("small.bin", 4_096),
        ("large.bin", 16_384),
      ]
    )

    harness.session.startScan()
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }
    await harness.scanner.yield(batch)
    await eventually {
      harness.session.largestItems.map(\.name) == [
        "large.bin",
        "small.bin",
      ]
    }

    #expect(harness.session.scanState == .scanning(batch.progress))
    await harness.scanner.finish()
  }

  @Test
  func givenAccessibleItemsAndIssues_whenScannerFinishes_thenCompletedCountsAreHonest()
    async
  {
    let harness = ExplorerSessionHarness()
    let batch = harness.batchWithOneItemAndOneIssue()

    harness.session.startScan()
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }
    await harness.scanner.yield(batch)
    await harness.scanner.finish()
    await eventually {
      harness.session.scanState
        == .completed(
          ScanCompletion(
            accessibleItemCount: 1,
            issueCount: 1
          )
        )
    }

    #expect(harness.session.largestItems.map(\.name) == ["accessible.bin"])
    #expect(await harness.index.candidateCount == 0)
  }

  @Test
  func givenCandidateSnapshot_whenScannerFails_thenCandidateIsDiscardedAndStateFails()
    async
  {
    let harness = ExplorerSessionHarness()
    let batch = harness.batch(namesAndSizes: [("partial.bin", 4_096)])

    harness.session.startScan()
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }
    await harness.scanner.yield(batch)
    await eventually {
      harness.session.largestItems.map(\.name) == ["partial.bin"]
    }
    await harness.scanner.fail(ControlledScanError.failed)
    await eventually {
      harness.session.scanState
        == .failed(
          ScanFailure(message: "The scan couldn’t be completed.")
        )
    }

    #expect(harness.session.largestItems.isEmpty)
    #expect(await harness.index.candidateCount == 0)
  }

  @Test
  func givenCompletedScanWithManyRootChildren_whenTreeAppears_thenOnlyFirstRootPageLoads()
    async throws
  {
    let harness = ExplorerSessionHarness(rootChildCount: 201)

    await harness.completeScan()

    let root = try #require(harness.session.treeRoot)
    let page = try #require(harness.session.treePages[root.id])
    #expect(page.items.count == 200)
    #expect(page.nextOffset == 200)
    #expect(harness.session.expandedTreeItemIDs == [root.id])
  }

  @Test
  func givenExpandedSelectedTree_whenAdjacentPageArrives_thenDisclosureAndSelectionRemainStable()
    async throws
  {
    let harness = ExplorerSessionHarness(rootChildCount: 201)
    await harness.completeScan()
    let root = try #require(harness.session.treeRoot)
    let selectedID = try #require(
      harness.session.treePages[root.id]?.items.first?.id
    )
    harness.session.selectItem(selectedID)

    await harness.session.loadNextTreePage(for: root.id)

    #expect(harness.session.treePages[root.id]?.items.count == 201)
    #expect(harness.session.treePages[root.id]?.nextOffset == nil)
    #expect(harness.session.expandedTreeItemIDs == [root.id])
    #expect(harness.session.selectedItemID == selectedID)
  }

  @Test
  func givenUnloadedFolder_whenFolderIsExpanded_thenOnlyItsFirstDirectPageLoads()
    async throws
  {
    let harness = ExplorerSessionHarness(folderChildCount: 2)
    await harness.completeScan()
    let folderID = try #require(harness.nestedFolderID)
    #expect(harness.session.treePages[folderID] == nil)

    harness.session.setTreeItem(folderID, expanded: true)
    await eventually {
      harness.session.treePages[folderID]?.items.count == 2
    }

    #expect(harness.session.expandedTreeItemIDs.contains(folderID))
    harness.session.setTreeItem(folderID, expanded: false)
    #expect(!harness.session.expandedTreeItemIDs.contains(folderID))
    #expect(harness.session.treePages[folderID]?.items.count == 2)
  }

  @Test
  func givenLoadedTree_whenFolderPageFails_thenExistingRowsRemainAndPathFreeFailureAppears()
    async throws
  {
    let harness = ExplorerSessionHarness(
      folderChildCount: 1,
      failingNestedPage: true
    )
    await harness.completeScan()
    let root = try #require(harness.session.treeRoot)
    let rootPage = try #require(harness.session.treePages[root.id])
    let folderID = try #require(harness.nestedFolderID)

    harness.session.setTreeItem(folderID, expanded: true)
    await eventually {
      harness.session.treeLoadFailureMessage
        == "Some items couldn’t be loaded."
    }

    #expect(harness.session.treePages[root.id] == rootPage)
    #expect(harness.session.treePages[folderID] == nil)
  }

  @Test
  func givenAdjacentPageFailsOnce_whenFailureIsRetried_thenPageLoads()
    async throws
  {
    let harness = ExplorerSessionHarness(rootChildCount: 201)
    await harness.completeScan()
    let root = try #require(harness.session.treeRoot)
    await harness.index.failNextTreePage(for: root.id)

    await harness.session.loadNextTreePage(for: root.id)
    await eventually {
      harness.session.treeLoadFailureMessage
        == "Some items couldn’t be loaded."
    }
    await harness.session.retryFailedTreePages()

    #expect(harness.session.treePages[root.id]?.items.count == 201)
    #expect(harness.session.treePages[root.id]?.nextOffset == nil)
    #expect(harness.session.treeLoadFailureMessage == nil)
  }

  @Test
  func givenTwoParentPagesFail_whenFailuresAreRetried_thenBothPagesLoad()
    async throws
  {
    let harness = ExplorerSessionHarness(
      rootChildCount: 201,
      folderChildCount: 1
    )
    await harness.completeScan()
    let root = try #require(harness.session.treeRoot)
    let folderID = try #require(harness.nestedFolderID)
    await harness.index.failNextTreePage(for: root.id)
    await harness.session.loadNextTreePage(for: root.id)
    await harness.index.failNextTreePage(for: folderID)

    harness.session.setTreeItem(folderID, expanded: true)
    await eventually {
      await harness.index.remainingTreeFailureCount(for: folderID) == 0
    }
    await harness.session.retryFailedTreePages()

    #expect(harness.session.treePages[root.id]?.items.count == 202)
    #expect(harness.session.treePages[folderID]?.items.count == 1)
    #expect(harness.session.treeLoadFailureMessage == nil)
  }

  @Test
  func givenScanningSession_whenPauseAndResumeOccur_thenLifecycleTransitionsAreValid()
    async
  {
    let harness = ExplorerSessionHarness()
    let indexedBeforePause = harness.batch(
      namesAndSizes: [("before-pause.bin", 4_096)]
    )
    let indexedAfterResume = harness.batch(
      namesAndSizes: [("after-resume.bin", 8_192)],
      discoveredItemCount: 2
    )
    harness.session.startScan()
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }
    await harness.scanner.yield(indexedBeforePause)
    await eventually {
      harness.session.scanState == .scanning(indexedBeforePause.progress)
    }

    #expect(await harness.session.pauseScan())
    #expect(harness.session.scanState == .paused(indexedBeforePause.progress))
    #expect(await harness.session.resumeScan())
    #expect(harness.session.scanState == .resuming(indexedBeforePause.progress))
    await harness.scanner.yield(indexedAfterResume)
    await eventually {
      harness.session.scanState == .scanning(indexedAfterResume.progress)
    }
    #expect(await harness.index.candidateCount == 1)
    #expect(
      await harness.index.lifecycleEvents
        == ["cleanup", "begin"]
    )
    #expect(await harness.scanner.requestedScopes.count == 1)

    let expectedIDs = Set(
      (indexedBeforePause.items + indexedAfterResume.items).map(\.id)
    )
    let indexedIDs = harness.session.largestItems.map(\.id)
    #expect(indexedIDs.count == expectedIDs.count)
    #expect(Set(indexedIDs) == expectedIDs)

    await harness.scanner.finish()
  }

  @Test
  func givenPausedSession_whenCancelOccurs_thenCandidateIsDiscardedBeforeCancelled()
    async
  {
    let harness = ExplorerSessionHarness()
    harness.session.startScan()
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }
    #expect(await harness.session.pauseScan())

    #expect(await harness.session.cancelScan())

    #expect(harness.session.scanState == .cancelled)
    #expect(await harness.index.candidateCount == 0)
    #expect(
      await harness.index.lifecycleEvents
        == ["cleanup", "begin", "discard"]
    )
  }

  @Test
  func givenInvalidLifecycleState_whenControlIntentOccurs_thenNoCompetingWorkerStarts()
    async
  {
    let harness = ExplorerSessionHarness()

    #expect(!(await harness.session.pauseScan()))
    #expect(!(await harness.session.resumeScan()))
    #expect(!(await harness.session.cancelScan()))
    #expect(harness.session.startScan())
    #expect(!harness.session.startScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }
    #expect(await harness.session.pauseScan())
    #expect(!(await harness.session.pauseScan()))

    #expect(await harness.scanner.requestedScopes.count == 1)
    #expect(await harness.session.cancelScan())
  }

  @Test
  func givenActiveScan_whenReplacementStarts_thenCancellationFinishesBeforeNextCandidateBegins()
    async
  {
    let harness = ExplorerSessionHarness()
    harness.session.startScan()
    await eventually {
      await harness.scanner.requestedScopes.count == 1
    }

    #expect(await harness.session.replaceScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 2
    }

    #expect(
      await harness.index.lifecycleEvents
        == ["cleanup", "begin", "discard", "begin"]
    )
    #expect(await harness.index.candidateCount == 1)
    _ = await harness.session.cancelScan()
  }

  @Test
  func givenPausedScan_whenTimeAdvances_thenNoAdditionalBatchIsRequested()
    async
  {
    let harness = ExplorerSessionHarness()
    let batch = harness.batch(namesAndSizes: [("paused.bin", 4_096)])
    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.nextBatchRequestCount == 1
    }

    #expect(await harness.session.pauseScan())
    await harness.scanner.yield(batch)
    await eventually {
      harness.session.scanState == .paused(batch.progress)
    }
    try? await Task.sleep(for: .milliseconds(25))

    #expect(await harness.scanner.nextBatchRequestCount == 1)
    #expect(await harness.session.resumeScan())
    await eventually {
      await harness.scanner.nextBatchRequestCount == 2
    }
    await harness.scanner.finish()
  }

  @Test
  func givenActiveScan_whenCancelOccurs_thenCancellationCompletesWithinTwoSeconds()
    async
  {
    let harness = ExplorerSessionHarness()
    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.nextBatchRequestCount == 1
    }
    let clock = ContinuousClock()
    let startedAt = clock.now

    #expect(await harness.session.cancelScan())

    #expect(startedAt.duration(to: clock.now) < .seconds(2))
    #expect(harness.session.scanState == .cancelled)
    #expect(await harness.index.candidateCount == 0)
    #expect(
      await harness.index.lifecycleEvents
        == ["cleanup", "begin", "discard"]
    )
  }

  @Test
  func givenCompletedTree_whenReplacementIsScanning_thenCompletedTreeRemainsVisible()
    async throws
  {
    let harness = ExplorerSessionHarness(rootChildCount: 1)
    let completedBatch = harness.batch(
      namesAndSizes: [("completed.bin", 8_192)]
    )
    await harness.completeScan(batch: completedBatch)
    let completedRoot = try #require(harness.session.treeRoot)
    let completedPages = harness.session.treePages
    let completedLargestItems = harness.session.largestItems
    let selectedID = try #require(
      completedPages[completedRoot.id]?.items.first?.id
    )
    harness.session.selectItem(selectedID)

    #expect(await harness.session.replaceScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 2
    }
    let replacementBatch = harness.batch(
      namesAndSizes: [("replacement.bin", 16_384)]
    )
    await harness.scanner.yield(replacementBatch)
    await eventually {
      harness.session.scanState == .scanning(replacementBatch.progress)
    }

    #expect(harness.session.treeRoot == completedRoot)
    #expect(harness.session.treePages == completedPages)
    #expect(harness.session.expandedTreeItemIDs == [completedRoot.id])
    #expect(harness.session.selectedItemID == selectedID)
    #expect(harness.session.largestItems == completedLargestItems)
    _ = await harness.session.cancelScan()
  }

  @Test
  func givenCompletedTree_whenReplacementFailsOrCancels_thenCompletedTreeRemainsVisible()
    async throws
  {
    let harness = ExplorerSessionHarness(rootChildCount: 1)
    let completedBatch = harness.batch(
      namesAndSizes: [("completed.bin", 8_192)]
    )
    await harness.completeScan(batch: completedBatch)
    let completedRoot = try #require(harness.session.treeRoot)
    let completedPages = harness.session.treePages
    let completedLargestItems = harness.session.largestItems
    let selectedID = try #require(
      completedPages[completedRoot.id]?.items.first?.id
    )
    harness.session.selectItem(selectedID)
    let completedExpandedIDs = harness.session.expandedTreeItemIDs

    #expect(await harness.session.replaceScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 2
    }
    await harness.scanner.fail(ControlledScanError.failed)
    await eventually {
      if case .failed = harness.session.scanState {
        return true
      }
      return false
    }

    #expect(harness.session.treeRoot == completedRoot)
    #expect(harness.session.treePages == completedPages)
    #expect(harness.session.largestItems == completedLargestItems)
    #expect(harness.session.expandedTreeItemIDs == completedExpandedIDs)
    #expect(harness.session.selectedItemID == selectedID)

    #expect(await harness.session.replaceScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 3
    }
    #expect(await harness.session.cancelScan())

    #expect(harness.session.treeRoot == completedRoot)
    #expect(harness.session.treePages == completedPages)
    #expect(harness.session.largestItems == completedLargestItems)
    #expect(harness.session.expandedTreeItemIDs == completedExpandedIDs)
    #expect(harness.session.selectedItemID == selectedID)
  }

  @Test
  func givenFirstScanFails_whenNoCompletedTreeExists_thenCandidatePreviewIsCleared()
    async
  {
    let harness = ExplorerSessionHarness()
    let batch = harness.batch(
      namesAndSizes: [("partial.bin", 4_096)]
    )
    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.nextBatchRequestCount == 1
    }
    await harness.scanner.yield(batch)
    await eventually {
      harness.session.largestItems.map(\.name) == ["partial.bin"]
    }

    await harness.scanner.fail(ControlledScanError.failed)
    await eventually {
      if case .failed = harness.session.scanState {
        return true
      }
      return false
    }

    #expect(harness.session.largestItems.isEmpty)
    #expect(harness.session.treeRoot == nil)
    #expect(harness.session.treePages.isEmpty)
  }

  @Test
  func givenCompletedTreeAndReplacementCandidate_whenPromotionCompletes_thenNewTreeReplacesOldTree()
    async throws
  {
    let harness = ExplorerSessionHarness(rootChildCount: 1)
    let completedBatch = harness.batch(
      namesAndSizes: [("completed.bin", 8_192)]
    )
    await harness.completeScan(batch: completedBatch)
    let completedRoot = try #require(harness.session.treeRoot)
    let replacementTree = harness.replacementTree(
      rootName: "Replacement",
      childName: "replacement.bin"
    )
    await harness.index.enqueueTreeSnapshot(
      root: replacementTree.root,
      children: replacementTree.children
    )

    #expect(await harness.session.replaceScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 2
    }
    let replacementBatch = harness.batch(
      namesAndSizes: [("replacement.bin", 16_384)]
    )
    await harness.scanner.yield(replacementBatch)
    await eventually {
      harness.session.scanState == .scanning(replacementBatch.progress)
    }
    #expect(harness.session.treeRoot == completedRoot)
    #expect(harness.session.largestItems.map(\.name) == ["completed.bin"])

    await harness.scanner.finish()
    await eventually {
      harness.session.treeRoot == replacementTree.root
        && harness.session.scanState
          == .completed(
            ScanCompletion(
              accessibleItemCount: 1,
              issueCount: 0
            )
          )
    }

    #expect(
      harness.session.treePages[replacementTree.root.id]?.items.map(\.name)
        == ["replacement.bin"]
    )
    #expect(harness.session.largestItems.map(\.name) == ["replacement.bin"])
  }

  @Test
  func givenIdleOrCompletedSession_whenQuitIsRequested_thenTerminationIsImmediate()
    async
  {
    let harness = ExplorerSessionHarness()

    #expect(harness.session.requestQuit() == .terminateNow)
    #expect(!harness.session.isQuitConfirmationPresented)

    await harness.completeScan()

    #expect(harness.session.requestQuit() == .terminateNow)
    #expect(!harness.session.isQuitConfirmationPresented)
  }

  @Test
  func givenActiveScan_whenQuitIsRequestedAndDismissed_thenScanContinues()
    async
  {
    let harness = ExplorerSessionHarness()
    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.nextBatchRequestCount == 1
    }

    #expect(
      harness.session.requestQuit()
        == .confirmScanCancellation
    )
    #expect(harness.session.isQuitConfirmationPresented)
    harness.session.dismissQuitConfirmation()

    #expect(!harness.session.isQuitConfirmationPresented)
    #expect(harness.session.scanState == .scanning(.initial))
    #expect(await harness.index.candidateCount == 1)
    _ = await harness.session.cancelScan()
  }

  @Test
  func givenPausedScan_whenQuitIsConfirmed_thenCancellationFinishesBeforeTermination()
    async
  {
    let harness = ExplorerSessionHarness()
    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.nextBatchRequestCount == 1
    }
    #expect(await harness.session.pauseScan())
    #expect(
      harness.session.requestQuit()
        == .confirmScanCancellation
    )

    #expect(await harness.session.confirmQuit())

    #expect(!harness.session.isQuitConfirmationPresented)
    #expect(harness.session.scanState == .cancelled)
    #expect(await harness.index.candidateCount == 0)
    #expect(
      await harness.index.lifecycleEvents
        == ["cleanup", "begin", "discard"]
    )
  }

  @Test
  func givenPromotionInProgress_whenCancelOccurs_thenCandidateRollsBackWithoutCompletion()
    async
  {
    let harness = ExplorerSessionHarness()
    await harness.index.blockNextPromotion()
    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.nextBatchRequestCount == 1
    }
    await harness.scanner.finish()
    await eventually {
      await harness.index.isPromotionBlocked
    }

    let cancellation = Task {
      await harness.session.cancelScan()
    }
    await eventually {
      harness.session.scanState == .cancelling(.initial)
    }
    await harness.index.unblockPromotion()

    #expect(await cancellation.value)
    #expect(harness.session.scanState == .cancelled)
    #expect(await harness.index.candidateCount == 0)
    #expect(
      await harness.index.lifecycleEvents
        == ["cleanup", "begin", "discard"]
    )
  }

  @Test
  func givenReplacementPresentationFails_whenPromotionRuns_thenPreviousSnapshotRemainsCoherent()
    async throws
  {
    let harness = ExplorerSessionHarness(rootChildCount: 1)
    let completedBatch = harness.batch(
      namesAndSizes: [("completed.bin", 8_192)]
    )
    await harness.completeScan(batch: completedBatch)
    let completedRoot = try #require(harness.session.treeRoot)
    let completedPages = harness.session.treePages
    let completedLargestItems = harness.session.largestItems
    await harness.index.failNextPromotionPresentation()

    #expect(await harness.session.replaceScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 2
    }
    await harness.scanner.yield(
      harness.batch(
        namesAndSizes: [("replacement.bin", 16_384)]
      )
    )
    await harness.scanner.finish()
    await eventually {
      if case .failed = harness.session.scanState {
        return true
      }
      return false
    }

    #expect(harness.session.treeRoot == completedRoot)
    #expect(harness.session.treePages == completedPages)
    #expect(harness.session.largestItems == completedLargestItems)
    #expect(await harness.index.candidateCount == 0)
    #expect(
      await harness.index.lifecycleEvents
        == ["cleanup", "begin", "promote", "begin", "discard"]
    )
  }

  @Test
  func givenFailedScanAndTargetedDiscardFails_whenCleanupRuns_thenCandidateIsRemoved()
    async
  {
    let harness = ExplorerSessionHarness()
    await harness.index.failNextCandidateDiscard()
    #expect(harness.session.startScan())
    await eventually {
      await harness.scanner.nextBatchRequestCount == 1
    }

    await harness.scanner.fail(ControlledScanError.failed)
    await eventually {
      if case .failed = harness.session.scanState {
        return true
      }
      return false
    }

    #expect(await harness.index.candidateCount == 0)
    #expect(
      await harness.index.lifecycleEvents
        == ["cleanup", "begin", "discard-failed", "cleanup"]
    )
  }

  @Test
  func
    givenAnEligibleSelectedFile_whenTrashConfirmationBegins_thenItStatesNameFullPathDiskUsedAndNoDescendantCount()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: fileURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }

    await session.beginTrashConfirmation(child.id)

    let confirmation = try #require(session.pendingTrashConfirmation)
    #expect(confirmation.itemID == child.id)
    #expect(confirmation.name == "note.txt")
    #expect(confirmation.path == fileURL.path(percentEncoded: false))
    #expect(confirmation.diskUsedBytes == 5)
    #expect(confirmation.descendantCount == nil)
    #expect(!confirmation.warnsAboutCloudSync)
  }

  @Test
  func givenACloudOnlySelectedFile_whenTrashConfirmationBegins_thenItWarnsAboutCloudSync()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: fileURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false,
      isCloudOnly: true
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }

    await session.beginTrashConfirmation(child.id)

    let confirmation = try #require(session.pendingTrashConfirmation)
    #expect(confirmation.warnsAboutCloudSync)
  }

  @Test
  func
    givenAnEligibleSelectedFolderWithChildren_whenTrashConfirmationBegins_thenItStatesDescendantCountAndAggregatedDiskUsed()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let nestedDirectory = directory.appending(path: "notes", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: nestedDirectory,
      withIntermediateDirectories: true
    )
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let folder = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: nestedDirectory,
      name: "notes",
      kind: .folder,
      diskUsedBytes: 4_096,
      apparentSizeBytes: 4_096,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: false
    )
    let leaf = StorageTreeItem(
      id: UUID(),
      parentID: folder.id,
      location: nestedDirectory.appending(path: "one.txt"),
      name: "one.txt",
      kind: .file,
      diskUsedBytes: 10,
      apparentSizeBytes: 10,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [folder], folder.id: [leaf]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }

    await session.beginTrashConfirmation(folder.id)

    let confirmation = try #require(session.pendingTrashConfirmation)
    #expect(confirmation.descendantCount == 1)
    #expect(confirmation.diskUsedBytes == 4_096)
  }

  @Test
  func givenAPendingTrashConfirmation_whenConfirmed_thenTheItemAndItsCachedStateAreRemoved()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: fileURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    await session.beginTrashConfirmation(child.id)

    let succeeded = await session.confirmTrash()

    #expect(succeeded)
    #expect(session.pendingTrashConfirmation == nil)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    #expect(session.treePages[root.id]?.items.isEmpty == true)
    #expect(session.selectedItemID == nil)
    #expect(session.trashSuccessMessage == "Moved to Trash")
  }

  @Test
  func givenAVisibleTrashSuccessMessage_whenDismissed_thenItClears() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: fileURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    await session.beginTrashConfirmation(child.id)
    _ = await session.confirmTrash()

    session.dismissTrashSuccessMessage()

    #expect(session.trashSuccessMessage == nil)
  }

  @Test
  func
    givenATargetReplacedWhileConfirmationIsOpen_whenConfirmed_thenItRejectsWithoutTrashingTheReplacement()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: fileURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    await session.beginTrashConfirmation(child.id)
    try FileManager.default.removeItem(at: fileURL)
    try Data("replaced".utf8).write(to: fileURL)

    let succeeded = await session.confirmTrash()

    #expect(!succeeded)
    #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    #expect(
      try Data(contentsOf: fileURL) == Data("replaced".utf8),
      "the replacement file must remain untouched"
    )
  }

  @Test
  func givenAPendingTrashConfirmation_whenDismissed_thenNothingIsMutatedAndStateClears()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: directory,
      name: directory.lastPathComponent,
      kind: .folder,
      diskUsedBytes: 0,
      apparentSizeBytes: 0,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: fileURL,
      name: "note.txt",
      kind: .file,
      diskUsedBytes: 5,
      apparentSizeBytes: 5,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: [root.id: [child]]
    )
    let scanner = ControlledFileSystemScanner()
    let session = ExplorerSession(
      homeDirectoryURL: directory,
      scanner: scanner,
      snapshotIndex: index
    )
    await session.waitForLaunchPreparation()
    session.startScan()
    await eventually { await scanner.requestedScopes.count == 1 }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState { true } else { false }
    }
    await session.beginTrashConfirmation(child.id)

    session.dismissTrashConfirmation()

    #expect(session.pendingTrashConfirmation == nil)
    #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    #expect(session.treePages[root.id]?.items.count == 1)
  }
}

@MainActor
private struct ExplorerSessionHarness {
  let homeDirectoryURL: URL
  let scanner: ControlledFileSystemScanner
  let index: InMemoryScanSnapshotIndex
  let session: ExplorerSession
  let nestedFolderID: UUID?

  init(
    rootChildCount: Int = 0,
    folderChildCount: Int = 0,
    failingNestedPage: Bool = false,
    scopeAuthorizer: (any ScanScopeAuthorizing)? = nil,
    customScopeBookmarkStore: (any CustomScopeBookmarking)? = nil
  ) {
    let homeDirectoryURL = URL(
      fileURLWithPath: "/Users/tester",
      isDirectory: true
    )
    let scanner = ControlledFileSystemScanner()
    let nestedFolderID = folderChildCount > 0 ? UUID() : nil
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: homeDirectoryURL,
      name: homeDirectoryURL.lastPathComponent,
      kind: .folder,
      diskUsedBytes: nil,
      apparentSizeBytes: nil,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: rootChildCount > 0 || nestedFolderID != nil,
      isRoot: true
    )
    var rootChildren = (0..<rootChildCount).map { index in
      StorageTreeItem(
        id: UUID(),
        parentID: root.id,
        location: homeDirectoryURL.appending(path: "item-\(index).bin"),
        name: "item-\(index).bin",
        kind: .file,
        diskUsedBytes: Int64(rootChildCount - index),
        apparentSizeBytes: Int64(rootChildCount - index),
        isDiskUsedIncomplete: false,
        isApparentSizeIncomplete: false,
        hasChildren: false,
        isRoot: false
      )
    }
    var treeChildren: [UUID: [StorageTreeItem]] = [:]
    if let nestedFolderID {
      let folder = StorageTreeItem(
        id: nestedFolderID,
        parentID: root.id,
        location: homeDirectoryURL.appending(
          path: "Nested",
          directoryHint: .isDirectory
        ),
        name: "Nested",
        kind: .folder,
        diskUsedBytes: Int64(folderChildCount),
        apparentSizeBytes: Int64(folderChildCount),
        isDiskUsedIncomplete: false,
        isApparentSizeIncomplete: false,
        hasChildren: true,
        isRoot: false
      )
      rootChildren.insert(folder, at: 0)
      treeChildren[nestedFolderID] = (0..<folderChildCount).map {
        childIndex in
        StorageTreeItem(
          id: UUID(),
          parentID: nestedFolderID,
          location: folder.location.appending(
            path: "child-\(childIndex).bin"
          ),
          name: "child-\(childIndex).bin",
          kind: .file,
          diskUsedBytes: Int64(folderChildCount - childIndex),
          apparentSizeBytes: Int64(folderChildCount - childIndex),
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: false,
          isRoot: false
        )
      }
    }
    treeChildren[root.id] = rootChildren
    let index = InMemoryScanSnapshotIndex(
      treeRoot: root,
      treeChildren: treeChildren,
      failingTreeParentIDs:
        failingNestedPage
        ? Set([nestedFolderID].compactMap(\.self))
        : []
    )

    self.homeDirectoryURL = homeDirectoryURL
    self.scanner = scanner
    self.index = index
    self.nestedFolderID = nestedFolderID
    session = ExplorerSession(
      homeDirectoryURL: homeDirectoryURL,
      scanner: scanner,
      snapshotIndex: index,
      scopeAuthorizer: scopeAuthorizer,
      customScopeBookmarkStore: customScopeBookmarkStore
    )
  }

  func completeScan(batch: FileSystemScanBatch? = nil) async {
    session.startScan()
    await eventually {
      await scanner.requestedScopes.count == 1
    }
    if let batch {
      await scanner.yield(batch)
      await eventually {
        session.scanState == .scanning(batch.progress)
      }
    }
    await scanner.finish()
    await eventually {
      if case .completed = session.scanState {
        return true
      }
      return false
    }
  }

  func batch(
    namesAndSizes: [(name: String, diskUsedBytes: Int64)],
    discoveredItemCount: Int? = nil
  ) -> FileSystemScanBatch {
    let items = namesAndSizes.map { name, diskUsedBytes in
      ScannedItem(
        id: UUID(),
        parentPath: homeDirectoryURL.path(percentEncoded: false),
        location: homeDirectoryURL.appending(path: name),
        name: name,
        kind: .file,
        diskUsedBytes: diskUsedBytes,
        apparentSizeBytes: diskUsedBytes,
        isHidden: false
      )
    }
    return FileSystemScanBatch(
      items: items,
      issues: [],
      progress: ScanProgress(
        discoveredItemCount: discoveredItemCount ?? items.count,
        issueCount: 0,
        currentArea: homeDirectoryURL
      )
    )
  }

  func batchWithOneItemAndOneIssue() -> FileSystemScanBatch {
    let itemURL = homeDirectoryURL.appending(path: "accessible.bin")
    let issueURL = homeDirectoryURL.appending(path: "restricted")
    return FileSystemScanBatch(
      items: [
        ScannedItem(
          id: UUID(),
          parentPath: homeDirectoryURL.path(percentEncoded: false),
          location: itemURL,
          name: itemURL.lastPathComponent,
          kind: .file,
          diskUsedBytes: 8_192,
          apparentSizeBytes: 8_192,
          isHidden: false
        )
      ],
      issues: [
        ScanIssue(
          location: issueURL,
          kind: .accessDenied,
          message: "The item could not be accessed."
        )
      ],
      progress: ScanProgress(
        discoveredItemCount: 1,
        issueCount: 1,
        currentArea: homeDirectoryURL
      )
    )
  }

  func replacementTree(
    rootName: String,
    childName: String
  ) -> (
    root: StorageTreeItem,
    children: [UUID: [StorageTreeItem]]
  ) {
    let rootURL = homeDirectoryURL.appending(
      path: rootName,
      directoryHint: .isDirectory
    )
    let root = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: rootURL,
      name: rootName,
      kind: .folder,
      diskUsedBytes: 16_384,
      apparentSizeBytes: 16_384,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: rootURL.appending(
        path: childName,
        directoryHint: .notDirectory
      ),
      name: childName,
      kind: .file,
      diskUsedBytes: 16_384,
      apparentSizeBytes: 16_384,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    return (root, [root.id: [child]])
  }
}

private enum ControlledBookmarkError: Error {
  case failed
}

private final class ControlledCustomScopeBookmarkStore:
  CustomScopeBookmarking,
  @unchecked Sendable
{
  private(set) var approvedLocations: [URL] = []
  private let reference: CustomScopeReference?
  private let error: (any Error)?

  init(
    reference: CustomScopeReference? = nil,
    error: (any Error)? = nil
  ) {
    self.reference = reference
    self.error = error
  }

  var currentReference: CustomScopeReference? {
    reference
  }

  func replaceApprovedLocation(_ location: URL) throws
    -> CustomScopeReference
  {
    if let error {
      throw error
    }
    approvedLocations.append(location)
    return try #require(reference)
  }

  func removeApprovedLocation() {}

  func resolve(_ reference: CustomScopeReference) throws -> URL {
    reference.lastKnownLocation
  }
}

extension ScanScope {
  fileprivate static func testScope(
    kind: Kind,
    path: String,
    volumeID: String
  ) -> Self {
    Self(
      kind: kind,
      location: URL(filePath: path, directoryHint: .isDirectory),
      volumeIdentity: ScanVolumeIdentity(rawValue: volumeID),
      volumeCharacteristics: ScanVolumeCharacteristics(
        isInternal: kind != .custom,
        isReadOnly: false,
        isRemovable: kind == .custom
      )
    )
  }
}

private struct FixedDateProvider: DateProviding {
  let date: Date

  init(now: Date) {
    date = now
  }

  func now() -> Date {
    date
  }
}

private final class MutableExplorerDateProvider: DateProviding, @unchecked Sendable {
  private var date: Date

  init(now: Date) {
    date = now
  }

  func now() -> Date {
    date
  }

  func advance(to date: Date) {
    self.date = date
  }
}

private func cachedSnapshot(
  scope: ScanScope,
  completedAt: Date = Date(timeIntervalSince1970: 1_754_049_600)
) throws -> CachedScanSnapshot {
  let root = StorageTreeItem(
    id: UUID(),
    parentID: nil,
    location: scope.location,
    name: scope.location.lastPathComponent,
    kind: .folder,
    diskUsedBytes: 4_096,
    apparentSizeBytes: 4_096,
    isDiskUsedIncomplete: false,
    isApparentSizeIncomplete: false,
    hasChildren: false,
    isRoot: true
  )
  return CachedScanSnapshot(
    scanID: ScanID(rawValue: UUID()),
    scope: scope,
    completion: ScanCompletion(accessibleItemCount: 1, issueCount: 0),
    completedAt: completedAt,
    expiresAt: completedAt.addingTimeInterval(86_400),
    largestItems: [
      StorageItemSummary(
        id: UUID(),
        location: scope.location.appending(path: "largest.bin"),
        name: "largest.bin",
        kind: .file,
        diskUsedBytes: 4_096
      )
    ],
    treeRoot: root,
    rootPage: StorageTreePage(parentID: root.id, items: [], nextOffset: nil)
  )
}
