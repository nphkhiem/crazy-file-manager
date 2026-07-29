import Foundation

struct ScanID: Hashable, Sendable {
  let rawValue: UUID
}

enum StorageItemKind: Int, Equatable, Sendable {
  case file
  case folder
  case symbolicLink
  case other
}

struct ScannedItem: Equatable, Sendable {
  let id: UUID
  let parentPath: String?
  let location: URL
  let name: String
  let kind: StorageItemKind
  let diskUsedBytes: Int64?
  let apparentSizeBytes: Int64?
  let isHidden: Bool
}

struct StorageItemSummary: Identifiable, Equatable, Sendable {
  let id: UUID
  let location: URL
  let name: String
  let kind: StorageItemKind
  let diskUsedBytes: Int64?
}
