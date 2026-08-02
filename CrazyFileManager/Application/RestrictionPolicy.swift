import Foundation

enum RestrictionPolicy {
  static func classify(
    path: String,
    kind: StorageItemKind,
    isRoot: Bool,
    isPackageDescendant: Bool,
    isShared: Bool,
    volume: ScanVolumeCharacteristics
  ) -> ItemSafetyState {
    if isRoot {
      return .restricted(.unsupported)
    }
    if kind == .other {
      return .restricted(.unsupported)
    }
    let normalizedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
    if normalizedPath == "/Volumes" {
      return .restricted(.operatingSystemProtected)
    }
    for prefix in Self.operatingSystemProtectedPrefixes {
      if normalizedPath == prefix || normalizedPath.hasPrefix(prefix + "/") {
        return .restricted(.operatingSystemProtected)
      }
    }
    for prefix in Self.applicationManagedPrefixes {
      if normalizedPath == prefix || normalizedPath.hasPrefix(prefix + "/") {
        return .restricted(.applicationManaged)
      }
    }
    if Self.isHomeLibraryManaged(normalizedPath) {
      return .restricted(.applicationManaged)
    }
    if isPackageDescendant {
      return .restricted(.packageInternal)
    }
    if isShared {
      return .restricted(.highRisk)
    }
    if volume.isReadOnly == true {
      return .restricted(.readOnlyVolume)
    }
    return .normal
  }

  static func capability(for state: ItemSafetyState) -> ItemCapability {
    guard case .restricted(let reason) = state else {
      return ItemCapability(
        canRename: true,
        cannotRenameReason: nil,
        canTrash: true,
        cannotTrashReason: nil
      )
    }
    let reasonText = reasonText(for: reason)
    return ItemCapability(
      canRename: false,
      cannotRenameReason: reasonText,
      canTrash: false,
      cannotTrashReason: reasonText
    )
  }

  private static func reasonText(for reason: RestrictionReason) -> String {
    switch reason {
    case .operatingSystemProtected:
      "Protected by the operating system."
    case .applicationManaged:
      "Managed by another app."
    case .packageInternal:
      "Inside a package."
    case .highRisk:
      "Shared with other locations."
    case .readOnlyVolume:
      "On a read-only volume."
    case .unsupported:
      "Not supported."
    }
  }

  private static let operatingSystemProtectedPrefixes: [String] = [
    "/System",
    "/Library/Extensions",
    "/usr",
    "/bin",
    "/sbin",
    "/private/var/db",
  ]

  private static let applicationManagedPrefixes: [String] = [
    "/Applications"
  ]

  private static let homeLibrarySubdirectories: Set<String> = [
    "Application Support",
    "Containers",
    "Caches",
  ]

  private static func isHomeLibraryManaged(_ path: String) -> Bool {
    let components = path.split(separator: "/", omittingEmptySubsequences: true)
    guard
      components.count >= 4,
      components[0] == "Users",
      components[2] == "Library"
    else {
      return false
    }
    return Self.homeLibrarySubdirectories.contains(String(components[3]))
  }
}
