import Foundation

struct ScanScope: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case homeFolder
  }

  let kind: Kind
  let location: URL

  static func homeFolder(_ location: URL) -> Self {
    Self(kind: .homeFolder, location: location.standardizedFileURL)
  }
}
