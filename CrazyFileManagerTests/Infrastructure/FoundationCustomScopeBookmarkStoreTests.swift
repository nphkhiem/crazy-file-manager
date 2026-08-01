import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Foundation Custom Scope Bookmark Store")
struct FoundationCustomScopeBookmarkStoreTests {
  @Test
  func givenTwoApprovedLocations_whenStoreIsRecreated_thenOnlyLatestBookmarkResolves()
    throws
  {
    let suiteName = "CrazyFileManagerBookmarkTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let fixture = try DisposableBookmarkFixture()
    defer { try? fixture.remove() }
    let firstStore = FoundationCustomScopeBookmarkStore(defaults: defaults)

    let firstReference = try firstStore.replaceApprovedLocation(
      fixture.firstLocation
    )
    let latestReference = try firstStore.replaceApprovedLocation(
      fixture.latestLocation
    )
    let recreatedStore = FoundationCustomScopeBookmarkStore(
      defaults: defaults
    )

    #expect(recreatedStore.currentReference == latestReference)
    #expect(
      try recreatedStore.resolve(latestReference).standardizedFileURL
        == fixture.latestLocation.standardizedFileURL
    )
    #expect(throws: CustomScopeBookmarkError.referenceReplaced) {
      try recreatedStore.resolve(firstReference)
    }
  }
}

private struct DisposableBookmarkFixture {
  let directory: URL
  let firstLocation: URL
  let latestLocation: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory.appending(
      path: "CrazyFileManagerBookmarkTests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    firstLocation = directory.appending(
      path: "First",
      directoryHint: .isDirectory
    )
    latestLocation = directory.appending(
      path: "Latest",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
      at: firstLocation,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: latestLocation,
      withIntermediateDirectories: true
    )
  }

  func remove() throws {
    try FileManager.default.removeItem(at: directory)
  }
}
