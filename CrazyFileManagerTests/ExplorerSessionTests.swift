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
}

@MainActor
private struct ExplorerSessionHarness {
  let homeDirectoryURL: URL
  let scanner: ControlledFileSystemScanner
  let index: InMemoryScanSnapshotIndex
  let session: ExplorerSession

  init() {
    let homeDirectoryURL = URL(
      fileURLWithPath: "/Users/tester",
      isDirectory: true
    )
    let scanner = ControlledFileSystemScanner()
    let index = InMemoryScanSnapshotIndex()

    self.homeDirectoryURL = homeDirectoryURL
    self.scanner = scanner
    self.index = index
    session = ExplorerSession(
      homeDirectoryURL: homeDirectoryURL,
      scanner: scanner,
      snapshotIndex: index
    )
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
