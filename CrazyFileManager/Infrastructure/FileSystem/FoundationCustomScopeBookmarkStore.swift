import Foundation

final class FoundationCustomScopeBookmarkStore:
  CustomScopeBookmarking,
  @unchecked Sendable
{
  private struct StoredBookmark: Codable {
    let bookmarkData: Data
    let displayName: String
    let lastKnownLocation: URL

    var reference: CustomScopeReference {
      CustomScopeReference(
        displayName: displayName,
        lastKnownLocation: lastKnownLocation
      )
    }
  }

  private static let storageKey = "approvedCustomScanScope"

  private let defaults: UserDefaults
  private let lock = NSLock()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var currentReference: CustomScopeReference? {
    lock.withLock {
      storedBookmark()?.reference
    }
  }

  func replaceApprovedLocation(_ location: URL) throws
    -> CustomScopeReference
  {
    try lock.withLock {
      let bookmarkData = try location.bookmarkData(
        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      let bookmark = StoredBookmark(
        bookmarkData: bookmarkData,
        displayName: location.lastPathComponent.isEmpty
          ? location.path(percentEncoded: false)
          : location.lastPathComponent,
        lastKnownLocation: location
      )
      try store(bookmark)
      return bookmark.reference
    }
  }

  func removeApprovedLocation() {
    lock.withLock {
      defaults.removeObject(forKey: Self.storageKey)
    }
  }

  func resolve(_ reference: CustomScopeReference) throws -> URL {
    try lock.withLock {
      guard let bookmark = storedBookmark() else {
        throw CustomScopeBookmarkError.missing
      }
      guard bookmark.reference == reference else {
        throw CustomScopeBookmarkError.referenceReplaced
      }

      var isStale = false
      let location = try URL(
        resolvingBookmarkData: bookmark.bookmarkData,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      if isStale {
        let refreshedData = try location.bookmarkData(
          options: [
            .withSecurityScope,
            .securityScopeAllowOnlyReadAccess,
          ],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        try store(
          StoredBookmark(
            bookmarkData: refreshedData,
            displayName: location.lastPathComponent,
            lastKnownLocation: location
          )
        )
      }
      return location
    }
  }

  private func storedBookmark() -> StoredBookmark? {
    guard let data = defaults.data(forKey: Self.storageKey) else {
      return nil
    }
    return try? PropertyListDecoder().decode(
      StoredBookmark.self,
      from: data
    )
  }

  private func store(_ bookmark: StoredBookmark) throws {
    defaults.set(
      try PropertyListEncoder().encode(bookmark),
      forKey: Self.storageKey
    )
  }
}
