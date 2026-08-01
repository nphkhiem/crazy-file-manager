import Foundation

struct PromotedScanSnapshot: Equatable, Sendable {
  let largestItems: [StorageItemSummary]
  let treeRoot: StorageTreeItem
  let rootPage: StorageTreePage
}

protocol ScanSnapshotIndexing: Sendable {
  func removeCrashLeftoverCandidates() async throws
  func beginCandidate(for scope: ScanScope) async throws -> ScanID
  func append(_ batch: FileSystemScanBatch, to candidate: ScanID) async throws
  func largestItems(in candidate: ScanID, limit: Int) async throws -> [StorageItemSummary]
  func treeRoot(in scan: ScanID) async throws -> StorageTreeItem
  func directChildren(
    of parentID: UUID,
    in scan: ScanID,
    offset: Int,
    limit: Int
  ) async throws -> StorageTreePage
  @discardableResult
  func promoteCandidate(
    _ candidate: ScanID,
    expectedItemCount: Int,
    expectedIssueCount: Int,
    largestItemLimit: Int,
    treePageLimit: Int
  ) async throws -> PromotedScanSnapshot
  func discardCandidate(_ candidate: ScanID) async throws
}
