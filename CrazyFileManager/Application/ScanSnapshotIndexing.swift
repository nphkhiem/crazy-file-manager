import Foundation

struct PromotedScanSnapshot: Equatable, Sendable {
  let scanID: ScanID
  let scope: ScanScope
  let completion: ScanCompletion
  let completedAt: Date
  let expiresAt: Date
  let largestItems: [StorageItemSummary]
  let treeRoot: StorageTreeItem
  let rootPage: StorageTreePage
}

struct CachedScanSnapshot: Equatable, Sendable {
  let scanID: ScanID
  let scope: ScanScope
  let completion: ScanCompletion
  let completedAt: Date
  let expiresAt: Date
  let largestItems: [StorageItemSummary]
  let treeRoot: StorageTreeItem
  let rootPage: StorageTreePage
}

enum ScanCachePreparation: Equatable, Sendable {
  case empty
  case available(CachedScanSnapshot)
  case expired(previousScope: ScanScope, completedAt: Date)
  case cleanupFailed(previousScope: ScanScope?, completedAt: Date?)
  case reconstructed
}

protocol ScanSnapshotIndexing: Sendable {
  func removeCrashLeftoverCandidates() async throws
  func prepareCacheForLaunch(
    largestItemLimit: Int,
    treePageLimit: Int
  ) async throws -> ScanCachePreparation
  func refreshCompletedCache(
    largestItemLimit: Int,
    treePageLimit: Int
  ) async throws -> ScanCachePreparation
  func clearCompletedSnapshot() async throws
  func beginCandidate(for scope: ScanScope) async throws -> ScanID
  func append(_ batch: FileSystemScanBatch, to candidate: ScanID) async throws
  func largestItems(in candidate: ScanID, limit: Int) async throws -> [StorageItemSummary]
  func treeRoot(in scan: ScanID) async throws -> StorageTreeItem
  func itemDetail(for itemID: UUID, in scan: ScanID) async throws -> StorageItemDetail?
  func updateItemName(
    _ itemID: UUID,
    in scan: ScanID,
    newName: String,
    newPath: String
  ) async throws
  func descendantCount(of itemID: UUID, in scan: ScanID) async throws -> Int?
  func removeItem(_ itemID: UUID, in scan: ScanID) async throws
  func issues(in scan: ScanID, limit: Int) async throws -> [ScanIssue]
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
