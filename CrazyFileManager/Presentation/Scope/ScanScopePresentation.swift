import Foundation

struct ScanScopePresentation: Equatable {
  let title: String
  let location: String
  let statusText: String
  let systemImage: String
  let isRecommended: Bool
  let isScanEnabled: Bool
  let showsChooseAgain: Bool
  let scanButtonTitle: String

  static func resolve(_ description: ScanScopeDescription) -> Self {
    let title = title(for: description.selection)
    let isCustom: Bool
    switch description.selection {
    case .custom:
      isCustom = true
    case .homeFolder, .entireInternalDisk:
      isCustom = false
    }

    let location: URL
    let statusText: String
    let systemImage: String
    let isScanEnabled: Bool
    switch description.availability {
    case .available(let scope):
      location = scope.location
      statusText = availableStatus(for: scope)
      systemImage = imageName(for: scope.kind)
      isScanEnabled = true
    case .disconnected(let lastKnownLocation):
      location = lastKnownLocation
      statusText = "This location is disconnected or no longer available."
      systemImage = "externaldrive.badge.exclamationmark"
      isScanEnabled = false
    case .unsupported(let unsupportedLocation):
      location = unsupportedLocation
      statusText =
        "This volume does not provide the stable identity required for safe scanning."
      systemImage = "externaldrive.badge.exclamationmark"
      isScanEnabled = false
    }

    return Self(
      title: title,
      location: displayPath(for: location),
      statusText: statusText,
      systemImage: systemImage,
      isRecommended: description.selection == .homeFolder,
      isScanEnabled: isScanEnabled,
      showsChooseAgain: isCustom,
      scanButtonTitle: "Scan \(title)"
    )
  }

  private static func title(for selection: ScanScopeSelection) -> String {
    switch selection {
    case .homeFolder:
      "Home Folder"
    case .entireInternalDisk:
      "Entire Internal Disk"
    case .custom(let reference):
      reference.displayName
    }
  }

  private static func displayPath(for location: URL) -> String {
    let path = location.path(percentEncoded: false)
    guard path.count > 1, path.hasSuffix("/") else {
      return path
    }
    return String(path.dropLast())
  }

  private static func availableStatus(for scope: ScanScope) -> String {
    if scope.kind == .homeFolder {
      return "Recommended for a fast, private overview."
    }
    if scope.kind == .entireInternalDisk {
      return "Scans the startup disk. Some locations may remain unavailable."
    }
    switch (
      scope.volumeCharacteristics.isReadOnly,
      scope.volumeCharacteristics.isRemovable
    ) {
    case (true, true):
      return "Read-only removable volume. Keep it connected while scanning."
    case (true, _):
      return "Read-only location. Scanning does not modify it."
    case (_, true):
      return "Removable volume. Keep it connected while scanning."
    default:
      return "Ready to scan this location."
    }
  }

  private static func imageName(for kind: ScanScope.Kind) -> String {
    switch kind {
    case .homeFolder:
      "house.fill"
    case .entireInternalDisk:
      "internaldrive.fill"
    case .custom:
      "externaldrive.fill"
    }
  }
}

struct ScanScopePermissionGuidance: Equatable {
  let message: String
  let openSettingsTitle: String
  let dismissTitle: String

  static func resolve(
    _ selection: ScanScopeSelection
  ) -> ScanScopePermissionGuidance? {
    guard selection == .entireInternalDisk else {
      return nil
    }
    return Self(
      message:
        "macOS may restrict parts of the startup disk. Full Disk Access can improve coverage, but Crazy File Manager cannot detect, grant, or bypass that permission.",
      openSettingsTitle: "Open System Settings",
      dismissTitle: "Not Now"
    )
  }
}
