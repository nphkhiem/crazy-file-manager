import Foundation
import Testing

@testable import CrazyFileManager

@MainActor
@Suite("Explorer Session")
struct ExplorerSessionTests {
  @Test
  func givenHomeFolderURL_whenSessionIsCreated_thenSelectsProvidedHomeFolder() {
    let homeDirectoryURL = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    let session = ExplorerSession(homeDirectoryURL: homeDirectoryURL)

    #expect(session.selectedScope == .homeFolder(homeDirectoryURL))
  }

  @Test
  func givenNewSession_whenNoScanIsRequested_thenScanStateRemainsIdle() {
    let homeDirectoryURL = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    let session = ExplorerSession(homeDirectoryURL: homeDirectoryURL)

    #expect(session.scanState == .idle)
  }
}
