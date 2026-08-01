import Foundation

protocol ScanScopeAuthorizing: Sendable {
  func describe(_ selection: ScanScopeSelection) -> ScanScopeDescription
  func prepare(_ selection: ScanScopeSelection) -> ScanScopePreparation
}

protocol CustomScopeBookmarkResolving: Sendable {
  func resolve(_ reference: CustomScopeReference) throws -> URL
}

protocol ScanScopeAccessLeasing: Sendable {
  func finish()
}

struct PreparedScanScope: Sendable {
  let scope: ScanScope
  let accessLease: any ScanScopeAccessLeasing
}

enum ScanScopePreparation: Sendable {
  case ready(PreparedScanScope)
  case unavailable(ScanScopeDescription)

  var preparedScope: PreparedScanScope? {
    guard case .ready(let preparedScope) = self else {
      return nil
    }
    return preparedScope
  }
}
