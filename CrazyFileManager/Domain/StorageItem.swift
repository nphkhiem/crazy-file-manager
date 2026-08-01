import Foundation

struct ScanID: Hashable, Sendable {
  let rawValue: UUID
}

enum StorageItemKind: Int, Equatable, Sendable {
  case file
  case folder
  case symbolicLink
  case other
  case package
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
  let isCloudOnly: Bool
  let fileSystemIdentity: UUID?
  let hardLinkCount: Int?

  init(
    id: UUID,
    parentPath: String?,
    location: URL,
    name: String,
    kind: StorageItemKind,
    diskUsedBytes: Int64?,
    apparentSizeBytes: Int64?,
    isHidden: Bool,
    isCloudOnly: Bool = false,
    fileSystemIdentity: UUID? = nil,
    hardLinkCount: Int? = nil
  ) {
    self.id = id
    self.parentPath = parentPath
    self.location = location
    self.name = name
    self.kind = kind
    self.diskUsedBytes = diskUsedBytes
    self.apparentSizeBytes = apparentSizeBytes
    self.isHidden = isHidden
    self.isCloudOnly = isCloudOnly
    self.fileSystemIdentity = fileSystemIdentity
    self.hardLinkCount = hardLinkCount
  }
}

struct StorageItemSummary: Identifiable, Equatable, Sendable {
  let id: UUID
  let location: URL
  let name: String
  let kind: StorageItemKind
  let diskUsedBytes: Int64?
}
