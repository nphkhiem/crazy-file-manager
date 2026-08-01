import Foundation

protocol CustomScopeBookmarking: CustomScopeBookmarkResolving {
  var currentReference: CustomScopeReference? { get }

  func replaceApprovedLocation(_ location: URL) throws
    -> CustomScopeReference
  func removeApprovedLocation()
}

enum CustomScopeBookmarkError: Error {
  case missing
  case referenceReplaced
}
