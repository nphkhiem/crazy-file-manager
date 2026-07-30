import Foundation
import Testing

@testable import CrazyFileManager

@MainActor
@Suite("Explorer Session")
struct ExplorerSessionTests {
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
    harness.session.selectTreeItem(selectedID)

    await harness.session.loadNextTreePage(for: root.id)

    #expect(harness.session.treePages[root.id]?.items.count == 201)
    #expect(harness.session.treePages[root.id]?.nextOffset == nil)
    #expect(harness.session.expandedTreeItemIDs == [root.id])
    #expect(harness.session.selectedTreeItemID == selectedID)
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
    failingNestedPage: Bool = false
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
      snapshotIndex: index
    )
  }

  func completeScan() async {
    session.startScan()
    await eventually {
      await scanner.requestedScopes.count == 1
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
    namesAndSizes: [(name: String, diskUsedBytes: Int64)]
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
        discoveredItemCount: items.count,
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
}
