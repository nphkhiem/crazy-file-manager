import Foundation

struct UpdateMetadata: Equatable, Sendable, Codable {
  let formatVersion: Int
  let version: String
  let minimumSystemVersion: String
  let downloadURL: URL
  let releaseNotesURL: URL?
}

enum UpdateMetadataRejection: Equatable, Sendable {
  case invalidSignature
  case malformed
  case incompatibleFormatVersion
  case incompatibleSystemVersion
}

enum UpdateCheckOutcome: Equatable, Sendable {
  case upToDate
  case available(UpdateMetadata)
  case rejected(UpdateMetadataRejection)
  case networkFailure(String)
}
