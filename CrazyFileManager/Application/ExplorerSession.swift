import Foundation
import Observation

@MainActor
@Observable
final class ExplorerSession {
  private(set) var selectedScope: ScanScope
  private(set) var scanState: ScanState = .idle
  private(set) var largestItems: [StorageItemSummary] = []

  private static let largestItemLimit = 200
  private let scanner: any FileSystemScanning
  private let snapshotIndex: any ScanSnapshotIndexing
  private var scanTask: Task<Void, Never>?

  init(
    homeDirectoryURL: URL,
    scanner: any FileSystemScanning,
    snapshotIndex: any ScanSnapshotIndexing
  ) {
    selectedScope = .homeFolder(homeDirectoryURL)
    self.scanner = scanner
    self.snapshotIndex = snapshotIndex
  }

  @discardableResult
  func startScan() -> Bool {
    guard scanTask == nil else {
      return false
    }

    let scope = selectedScope
    scanState = .scanning(.initial)
    scanTask = Task(priority: .utility) { [weak self] in
      await self?.runScan(for: scope)
    }
    return true
  }

  private func runScan(for scope: ScanScope) async {
    var candidate: ScanID?
    do {
      let newCandidate = try await snapshotIndex.beginCandidate(for: scope)
      candidate = newCandidate
      let batches = await scanner.batches(for: scope)
      var latestProgress = ScanProgress.initial
      for try await batch in batches {
        try Task.checkCancellation()
        try await snapshotIndex.append(batch, to: newCandidate)
        largestItems = try await snapshotIndex.largestItems(
          in: newCandidate,
          limit: Self.largestItemLimit
        )
        latestProgress = batch.progress
        scanState = .scanning(batch.progress)
      }
      try await snapshotIndex.promoteCandidate(
        newCandidate,
        expectedItemCount: latestProgress.discoveredItemCount,
        expectedIssueCount: latestProgress.issueCount
      )
      largestItems = try await snapshotIndex.largestItems(
        in: newCandidate,
        limit: Self.largestItemLimit
      )
      scanState = .completed(
        ScanCompletion(
          accessibleItemCount: latestProgress.discoveredItemCount,
          issueCount: latestProgress.issueCount
        )
      )
    } catch {
      if let candidate {
        try? await snapshotIndex.discardCandidate(candidate)
      }
      largestItems = []
      scanState = .failed(
        ScanFailure(message: "The scan couldn’t be completed.")
      )
    }
    scanTask = nil
  }
}
