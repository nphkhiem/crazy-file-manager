import Foundation

struct ScanIssue: Equatable, Sendable {
  enum Kind: Int, Equatable, Sendable {
    case accessDenied
    case metadataUnavailable
    case volumeUnavailable
    case changed
    case consistency
  }

  let location: URL
  let kind: Kind
  let message: String
}

struct ScanProgress: Equatable, Sendable {
  let discoveredItemCount: Int
  let issueCount: Int
  let currentArea: URL?
  let fractionCompleted: Double?

  init(
    discoveredItemCount: Int,
    issueCount: Int,
    currentArea: URL?,
    fractionCompleted: Double? = nil
  ) {
    self.discoveredItemCount = discoveredItemCount
    self.issueCount = issueCount
    self.currentArea = currentArea
    self.fractionCompleted = fractionCompleted
  }

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
