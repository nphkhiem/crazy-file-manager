import Foundation

struct ScanIssue: Equatable, Sendable {
  enum Kind: Int, Equatable, Sendable {
    case accessDenied
    case metadataUnavailable
  }

  let location: URL
  let kind: Kind
  let message: String
}

struct ScanProgress: Equatable, Sendable {
  let discoveredItemCount: Int
  let issueCount: Int
  let currentArea: URL?

  static let initial = Self(
    discoveredItemCount: 0,
    issueCount: 0,
    currentArea: nil
  )
}

struct ScanCompletion: Equatable, Sendable {
  let accessibleItemCount: Int
  let issueCount: Int
}

struct FileSystemScanBatch: Equatable, Sendable {
  let items: [ScannedItem]
  let issues: [ScanIssue]
  let progress: ScanProgress
}
