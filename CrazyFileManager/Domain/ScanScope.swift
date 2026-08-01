import Foundation

struct ScanScope: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case homeFolder
    case entireInternalDisk
    case custom
  }

  let kind: Kind
  let location: URL
  let volumeIdentity: ScanVolumeIdentity
  let volumeCharacteristics: ScanVolumeCharacteristics

  static func homeFolder(_ location: URL) -> Self {
    Self(
      kind: .homeFolder,
      location: location.standardizedFileURL,
      volumeIdentity: ScanVolumeIdentity(
        rawValue: "unverified:\(location.standardizedFileURL.path(percentEncoded: false))"
      ),
      volumeCharacteristics: ScanVolumeCharacteristics(
        isInternal: nil,
        isReadOnly: nil,
        isRemovable: nil
      )
    )
  }
}

struct ScanVolumeIdentity: Equatable, Hashable, Sendable {
  let rawValue: String
}

struct ScanVolumeCharacteristics: Equatable, Sendable {
  let isInternal: Bool?
  let isReadOnly: Bool?
  let isRemovable: Bool?
}

struct CustomScopeReference: Equatable, Sendable {
  let displayName: String
  let lastKnownLocation: URL
}

enum ScanScopeSelection: Equatable, Sendable {
  case homeFolder
  case entireInternalDisk
  case custom(CustomScopeReference)
}

enum ScanScopeAvailability: Equatable, Sendable {
  case available(ScanScope)
  case disconnected(lastKnownLocation: URL)
  case unsupported(location: URL)

  var availableScope: ScanScope? {
    guard case .available(let scope) = self else {
      return nil
    }
    return scope
  }
}

struct ScanScopeDescription: Equatable, Sendable {
  let selection: ScanScopeSelection
  let availability: ScanScopeAvailability
}
