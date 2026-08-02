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
  let isShared: Bool
  let isHidden: Bool
  let isCloudOnly: Bool

  init(
    id: UUID,
    parentID: UUID?,
    location: URL,
    name: String,
    kind: StorageItemKind,
    diskUsedBytes: Int64?,
    apparentSizeBytes: Int64?,
    isDiskUsedIncomplete: Bool,
    isApparentSizeIncomplete: Bool,
    hasChildren: Bool,
    isRoot: Bool,
    isShared: Bool = false,
    isHidden: Bool = false,
    isCloudOnly: Bool = false
  ) {
    self.id = id
    self.parentID = parentID
    self.location = location
    self.name = name
    self.kind = kind
    self.diskUsedBytes = diskUsedBytes
    self.apparentSizeBytes = apparentSizeBytes
    self.isDiskUsedIncomplete = isDiskUsedIncomplete
    self.isApparentSizeIncomplete = isApparentSizeIncomplete
    self.hasChildren = hasChildren
    self.isRoot = isRoot
    self.isShared = isShared
    self.isHidden = isHidden
    self.isCloudOnly = isCloudOnly
  }
}

extension StorageTreeItem {
  func withRenamed(name: String, location: URL) -> StorageTreeItem {
    StorageTreeItem(
      id: id,
      parentID: parentID,
      location: location,
      name: name,
      kind: kind,
      diskUsedBytes: diskUsedBytes,
      apparentSizeBytes: apparentSizeBytes,
      isDiskUsedIncomplete: isDiskUsedIncomplete,
      isApparentSizeIncomplete: isApparentSizeIncomplete,
      hasChildren: hasChildren,
      isRoot: isRoot,
      isShared: isShared,
      isHidden: isHidden,
      isCloudOnly: isCloudOnly
    )
  }

  func withRelocated(to location: URL) -> StorageTreeItem {
    withRenamed(name: name, location: location)
  }
}

struct StorageTreePage: Equatable, Sendable {
  let parentID: UUID
  let items: [StorageTreeItem]
  let nextOffset: Int?
}

struct StorageItemDetail: Equatable, Sendable {
  let item: StorageTreeItem
  let volumeCharacteristics: ScanVolumeCharacteristics
}
