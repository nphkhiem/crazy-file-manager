import Foundation

enum RestrictionReason: Equatable, Sendable {
  case operatingSystemProtected
  case applicationManaged
  case packageInternal
  case highRisk
  case readOnlyVolume
  case unsupported
}

enum ItemSafetyState: Equatable, Sendable {
  case normal
  case restricted(RestrictionReason)
}

struct ItemCapability: Equatable, Sendable {
  let canRename: Bool
  let cannotRenameReason: String?
  let canTrash: Bool
  let cannotTrashReason: String?
}
