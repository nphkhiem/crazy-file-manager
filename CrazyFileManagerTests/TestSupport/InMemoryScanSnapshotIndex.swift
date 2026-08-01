import Foundation

@testable import CrazyFileManager

actor InMemoryScanSnapshotIndex: ScanSnapshotIndexing {
  private struct TreeConfiguration: Sendable {
    let root: StorageTreeItem
    let children: [UUID: [StorageTreeItem]]
  }

  private struct Snapshot: Sendable {
    var items: [ScannedItem] = []
    var issues: [ScanIssue] = []
    let treeRoot: StorageTreeItem
    let treeChildren: [UUID: [StorageTreeItem]]
  }

  private let configuredTreeRoot: StorageTreeItem?
  private let configuredTreeChildren: [UUID: [StorageTreeItem]]
  private var treeFailuresRemaining: [UUID: Int]
  private var candidates: [ScanID: Snapshot] = [:]
  private var completedSnapshots: [ScanID: Snapshot] = [:]
  private var queuedTreeConfigurations: [TreeConfiguration] = []
  private var blocksNextPromotion = false
  private(set) var isPromotionBlocked = false
  private var promotionContinuation: CheckedContinuation<Void, Never>?
  private var failsNextPromotionPresentation = false
  private var failsNextCandidateDiscard = false
  private(set) var lifecycleEvents: [String] = []
  private(set) var requestedScopes: [ScanScope] = []

  init(
    treeRoot: StorageTreeItem? = nil,
    treeChildren: [UUID: [StorageTreeItem]] = [:],
    failingTreeParentIDs: Set<UUID> = []
  ) {
    configuredTreeRoot = treeRoot
    configuredTreeChildren = treeChildren
    treeFailuresRemaining = [:]
    for parentID in failingTreeParentIDs {
      treeFailuresRemaining[parentID] = .max
    }
  }

  var candidateCount: Int {
    candidates.count
  }

  func removeCrashLeftoverCandidates() {
    candidates.removeAll()
    lifecycleEvents.append("cleanup")
  }

  func enqueueTreeSnapshot(
    root: StorageTreeItem,
    children: [UUID: [StorageTreeItem]]
  ) {
    queuedTreeConfigurations.append(
      TreeConfiguration(root: root, children: children)
    )
  }

  func blockNextPromotion() {
    blocksNextPromotion = true
  }

  func unblockPromotion() {
    promotionContinuation?.resume()
    promotionContinuation = nil
  }

  func failNextPromotionPresentation() {
    failsNextPromotionPresentation = true
  }

  func failNextCandidateDiscard() {
    failsNextCandidateDiscard = true
  }

  func failNextTreePage(for parentID: UUID) {
    treeFailuresRemaining[parentID] = 1
  }

  func remainingTreeFailureCount(for parentID: UUID) -> Int {
    treeFailuresRemaining[parentID] ?? 0
  }

  func beginCandidate(for scope: ScanScope) async throws -> ScanID {
    requestedScopes.append(scope)
    let candidate = ScanID(rawValue: UUID())
    let queuedConfiguration =
      queuedTreeConfigurations.isEmpty
      ? nil
      : queuedTreeConfigurations.removeFirst()
    let root =
      queuedConfiguration?.root
      ?? configuredTreeRoot
      ?? StorageTreeItem(
        id: UUID(),
        parentID: nil,
        location: scope.location,
        name: scope.location.lastPathComponent,
        kind: .folder,
        diskUsedBytes: nil,
        apparentSizeBytes: nil,
        isDiskUsedIncomplete: false,
        isApparentSizeIncomplete: false,
        hasChildren: false,
        isRoot: true
      )
    candidates[candidate] = Snapshot(
      treeRoot: root,
      treeChildren:
        queuedConfiguration?.children
        ?? configuredTreeChildren
    )
    lifecycleEvents.append("begin")
    return candidate
  }

  func append(
    _ batch: FileSystemScanBatch,
    to candidate: ScanID
  ) async throws {
    guard var snapshot = candidates[candidate] else {
      throw SnapshotIndexError.candidateNotFound
    }
    snapshot.items.append(contentsOf: batch.items)
    snapshot.issues.append(contentsOf: batch.issues)
    candidates[candidate] = snapshot
  }

  func largestItems(
    in candidate: ScanID,
    limit: Int
  ) async throws -> [StorageItemSummary] {
    guard
      let snapshot =
        candidates[candidate] ?? completedSnapshots[candidate]
    else {
      throw SnapshotIndexError.candidateNotFound
    }

    return largestItems(from: snapshot, limit: limit)
  }

  func treeRoot(in scan: ScanID) async throws -> StorageTreeItem {
    guard
      let snapshot = candidates[scan] ?? completedSnapshots[scan]
    else {
      throw SnapshotIndexError.candidateNotFound
    }
    return snapshot.treeRoot
  }

  func directChildren(
    of parentID: UUID,
    in scan: ScanID,
    offset: Int,
    limit: Int
  ) async throws -> StorageTreePage {
    let failuresRemaining = treeFailuresRemaining[parentID] ?? 0
    guard failuresRemaining == 0 else {
      if failuresRemaining != .max {
        treeFailuresRemaining[parentID] = failuresRemaining - 1
      }
      throw SnapshotIndexError.candidateNotFound
    }
    guard
      let snapshot = candidates[scan] ?? completedSnapshots[scan]
    else {
      throw SnapshotIndexError.candidateNotFound
    }
    return page(
      of: parentID,
      in: snapshot,
      offset: offset,
      limit: limit
    )
  }

  @discardableResult
  func promoteCandidate(
    _ candidate: ScanID,
    expectedItemCount: Int,
    expectedIssueCount: Int,
    largestItemLimit: Int = 200,
    treePageLimit: Int = 200
  ) async throws -> PromotedScanSnapshot {
    if blocksNextPromotion {
      blocksNextPromotion = false
      isPromotionBlocked = true
      await withCheckedContinuation { continuation in
        promotionContinuation = continuation
      }
      isPromotionBlocked = false
    }
    try Task.checkCancellation()
    guard let snapshot = candidates[candidate] else {
      throw SnapshotIndexError.candidateNotFound
    }
    guard snapshot.items.count == expectedItemCount else {
      throw SnapshotIndexError.itemCountMismatch(
        expected: expectedItemCount,
        actual: snapshot.items.count
      )
    }
    guard snapshot.issues.count == expectedIssueCount else {
      throw SnapshotIndexError.issueCountMismatch(
        expected: expectedIssueCount,
        actual: snapshot.issues.count
      )
    }

    let promotedSnapshot = PromotedScanSnapshot(
      largestItems: largestItems(
        from: snapshot,
        limit: largestItemLimit
      ),
      treeRoot: snapshot.treeRoot,
      rootPage: page(
        of: snapshot.treeRoot.id,
        in: snapshot,
        offset: 0,
        limit: treePageLimit
      )
    )
    if failsNextPromotionPresentation {
      failsNextPromotionPresentation = false
      throw SnapshotIndexError.integrityCheckFailed
    }
    try Task.checkCancellation()
    completedSnapshots = [candidate: snapshot]
    candidates.removeValue(forKey: candidate)
    lifecycleEvents.append("promote")
    return promotedSnapshot
  }

  func discardCandidate(_ candidate: ScanID) async throws {
    if failsNextCandidateDiscard {
      failsNextCandidateDiscard = false
      lifecycleEvents.append("discard-failed")
      throw SnapshotIndexError.statementFailed(code: 1)
    }
    candidates.removeValue(forKey: candidate)
    lifecycleEvents.append("discard")
  }

  private func largestItems(
    from snapshot: Snapshot,
    limit: Int
  ) -> [StorageItemSummary] {
    snapshot.items
      .sorted(by: sortsBefore)
      .prefix(max(0, limit))
      .map {
        StorageItemSummary(
          id: $0.id,
          location: $0.location,
          name: $0.name,
          kind: $0.kind,
          diskUsedBytes: $0.diskUsedBytes
        )
      }
  }

  private func page(
    of parentID: UUID,
    in snapshot: Snapshot,
    offset: Int,
    limit: Int
  ) -> StorageTreePage {
    let children = snapshot.treeChildren[parentID] ?? []
    let boundedOffset = min(max(0, offset), children.count)
    let boundedLimit = max(0, limit)
    let end = min(
      boundedOffset + min(boundedLimit, children.count),
      children.count
    )
    return StorageTreePage(
      parentID: parentID,
      items: Array(children[boundedOffset..<end]),
      nextOffset: end < children.count ? end : nil
    )
  }

  private func sortsBefore(_ lhs: ScannedItem, _ rhs: ScannedItem) -> Bool {
    switch (lhs.diskUsedBytes, rhs.diskUsedBytes) {
    case (.some(let lhsBytes), .some(let rhsBytes)):
      if lhsBytes != rhsBytes {
        return lhsBytes > rhsBytes
      }
    case (.some, .none):
      return true
    case (.none, .some):
      return false
    case (.none, .none):
      break
    }

    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
  }
}
