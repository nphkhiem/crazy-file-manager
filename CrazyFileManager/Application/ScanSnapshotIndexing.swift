import Foundation

protocol ScanSnapshotIndexing: Sendable {
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
  func promoteCandidate(
    _ candidate: ScanID,
    expectedItemCount: Int,
    expectedIssueCount: Int
  ) async throws
  func discardCandidate(_ candidate: ScanID) async throws
}
