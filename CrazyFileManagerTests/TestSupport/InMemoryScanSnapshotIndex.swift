import Foundation

@testable import CrazyFileManager

actor InMemoryScanSnapshotIndex: ScanSnapshotIndexing {
  private struct Snapshot: Sendable {
    var items: [ScannedItem] = []
    var issues: [ScanIssue] = []
  }

  private var candidates: [ScanID: Snapshot] = [:]
  private var completedSnapshots: [ScanID: Snapshot] = [:]

  var candidateCount: Int {
    candidates.count
  }

  func beginCandidate(for scope: ScanScope) async throws -> ScanID {
    let candidate = ScanID(rawValue: UUID())
    candidates[candidate] = Snapshot()
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
