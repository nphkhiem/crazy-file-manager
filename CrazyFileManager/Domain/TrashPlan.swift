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
  case rejected(reason: String)
}
