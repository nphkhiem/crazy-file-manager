import Foundation

@testable import CrazyFileManager

actor InMemoryScanSnapshotIndex: ScanSnapshotIndexing {
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

  func failNextTreePage(for parentID: UUID) {
    treeFailuresRemaining[parentID] = 1
  }

  func remainingTreeFailureCount(for parentID: UUID) -> Int {
    treeFailuresRemaining[parentID] ?? 0
  }

  func beginCandidate(for scope: ScanScope) async throws -> ScanID {
    let candidate = ScanID(rawValue: UUID())
    let root =
      configuredTreeRoot
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
      treeChildren: configuredTreeChildren
    )
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

    return snapshot.items
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

  func promoteCandidate(
    _ candidate: ScanID,
    expectedItemCount: Int,
    expectedIssueCount: Int
  ) async throws {
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

    completedSnapshots = [candidate: snapshot]
    candidates.removeValue(forKey: candidate)
  }

  func discardCandidate(_ candidate: ScanID) async throws {
    candidates.removeValue(forKey: candidate)
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
