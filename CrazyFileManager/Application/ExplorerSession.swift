import Foundation
import Observation

@MainActor
@Observable
final class ExplorerSession {
  private(set) var selectedScope: ScanScope
  private(set) var scanState: ScanState = .idle
  private(set) var largestItems: [StorageItemSummary] = []
  private(set) var treeRoot: StorageTreeItem?
  private(set) var treePages: [UUID: StorageTreePage] = [:]
  private(set) var expandedTreeItemIDs: Set<UUID> = []
  private(set) var selectedTreeItemID: UUID?
  private(set) var loadingTreeItemIDs: Set<UUID> = []
  private(set) var treeLoadFailureMessage: String?

  private static let largestItemLimit = 200
  private static let treePageSize = 200
  private let scanner: any FileSystemScanning
  private let snapshotIndex: any ScanSnapshotIndexing
  private var scanTask: Task<Void, Never>?
  private var completedScanID: ScanID?

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

  func selectTreeItem(_ itemID: UUID?) {
    selectedTreeItemID = itemID
  }

  func setTreeItem(_ itemID: UUID, expanded: Bool) {
    guard expanded else {
      expandedTreeItemIDs.remove(itemID)
      return
    }

    expandedTreeItemIDs.insert(itemID)
    guard treePages[itemID] == nil else {
      return
    }
    Task { [weak self] in
      await self?.loadTreePage(
        for: itemID,
        offset: 0,
        existingPage: nil
      )
    }
  }

  func loadNextTreePage(for parentID: UUID) async {
    guard
      let currentPage = treePages[parentID],
      let nextOffset = currentPage.nextOffset
    else {
      return
    }

    await loadTreePage(
      for: parentID,
      offset: nextOffset,
      existingPage: currentPage
    )
  }

  private func loadTreePage(
    for parentID: UUID,
    offset: Int,
    existingPage: StorageTreePage?
  ) async {
    guard
      let completedScanID,
      !loadingTreeItemIDs.contains(parentID)
    else {
      return
    }

    loadingTreeItemIDs.insert(parentID)
    defer {
      loadingTreeItemIDs.remove(parentID)
    }
    treeLoadFailureMessage = nil

    do {
      let nextPage = try await snapshotIndex.directChildren(
        of: parentID,
        in: completedScanID,
        offset: offset,
        limit: Self.treePageSize
      )
      guard self.completedScanID == completedScanID else {
        return
      }
      let currentItems = existingPage?.items ?? []
      let existingIDs = Set(currentItems.map(\.id))
      let newItems = nextPage.items.filter {
        !existingIDs.contains($0.id)
      }
      treePages[parentID] = StorageTreePage(
        parentID: parentID,
        items: currentItems + newItems,
        nextOffset: nextPage.nextOffset
      )
    } catch {
      treeLoadFailureMessage = "Some items couldn’t be loaded."
    }
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
      let root = try await snapshotIndex.treeRoot(in: newCandidate)
      let rootPage = try await snapshotIndex.directChildren(
        of: root.id,
        in: newCandidate,
        offset: 0,
        limit: Self.treePageSize
      )
      treeRoot = root
      treePages = [root.id: rootPage]
      expandedTreeItemIDs = [root.id]
      completedScanID = newCandidate
      treeLoadFailureMessage = nil
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
      treeRoot = nil
      treePages = [:]
      expandedTreeItemIDs = []
      selectedTreeItemID = nil
      loadingTreeItemIDs = []
      treeLoadFailureMessage = nil
      completedScanID = nil
      scanState = .failed(
        ScanFailure(message: "The scan couldn’t be completed.")
      )
    }
    scanTask = nil
  }
}
