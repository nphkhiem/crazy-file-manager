import Foundation

struct StorageTreeItem: Identifiable, Equatable, Sendable {
  let id: UUID
  let parentID: UUID?
  let location: URL
  let name: String
  let kind: StorageItemKind
  let diskUsedBytes: Int64?
  let apparentSizeBytes: Int64?
  let isDiskUsedIncomplete: Bool
  let isApparentSizeIncomplete: Bool
  let hasChildren: Bool
  let isRoot: Bool
}

struct StorageTreePage: Equatable, Sendable {
  let parentID: UUID
  let items: [StorageTreeItem]
  let nextOffset: Int?
}
