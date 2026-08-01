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
    harness.session.selectTreeItem(selectedID)

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
    #expect(harness.session.selectedTreeItemID == selectedID)
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
    harness.session.selectTreeItem(selectedID)
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
    #expect(harness.session.selectedTreeItemID == selectedID)

    #expect(await harness.session.replaceScan())
    await eventually {
      await harness.scanner.requestedScopes.count == 3
    }
    #expect(await harness.session.cancelScan())

    #expect(harness.session.treeRoot == completedRoot)
    #expect(harness.session.treePages == completedPages)
    #expect(harness.session.largestItems == completedLargestItems)
    #expect(harness.session.expandedTreeItemIDs == completedExpandedIDs)
    #expect(harness.session.selectedTreeItemID == selectedID)
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
