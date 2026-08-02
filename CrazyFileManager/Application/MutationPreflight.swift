import Foundation

struct LiveMutationEvidence: Equatable, Sendable {
  let deviceNumber: Int
  let inodeNumber: Int
  let parentPath: String
  let volumeIdentifier: String?
}

protocol MutationEvidenceProviding: Sendable {
  func liveEvidence(at path: String) -> LiveMutationEvidence?
}

struct ExpectedMutationTarget: Equatable, Sendable {
  let scanID: ScanID
  let volumeIdentity: ScanVolumeIdentity
  let path: String
  let kind: StorageItemKind
  let expectedEvidence: LiveMutationEvidence
}

enum MutationPreflightResult: Equatable, Sendable {
  case accepted
  case rejected(reason: String)
}

enum MutationPreflight {
  static func validate(
    expected: ExpectedMutationTarget,
    liveEvidenceProvider: any MutationEvidenceProviding
  ) -> MutationPreflightResult {
    guard let currentEvidence = liveEvidenceProvider.liveEvidence(at: expected.path) else {
      return .rejected(reason: "This item can no longer be found.")
    }
    guard currentEvidence == expected.expectedEvidence else {
      return .rejected(reason: "This item has changed since it was last checked.")
    }
    return .accepted
  }
}
