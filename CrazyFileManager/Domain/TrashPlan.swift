import Foundation

struct TrashConfirmation: Equatable, Sendable {
  let itemID: UUID
  let name: String
  let path: String
  let diskUsedBytes: Int64?
  let descendantCount: Int?
  let warnsAboutCloudSync: Bool
}

enum TrashOutcome: Equatable, Sendable {
  case trashed
  case stale(reason: String)
  case failed(reason: String)
}

struct BulkTrashItemProblem: Equatable, Sendable {
  let itemID: UUID
  let name: String
  let reason: String
}

struct BulkTrashConfirmation: Equatable, Sendable {
  let eligibleItemIDs: [UUID]
  let combinedDiskUsedBytes: Int64?
  let hasIncompleteDiskUsed: Bool
  let exclusions: [BulkTrashItemProblem]
}

struct BulkTrashCompletion: Equatable, Sendable {
  let trashedItemIDs: [UUID]
  let excluded: [BulkTrashItemProblem]
  let failed: [BulkTrashItemProblem]
  let stale: [BulkTrashItemProblem]
}
