import Foundation
import Testing

@testable import CrazyFileManager

@MainActor
@Suite("Explorer Session")
struct ExplorerSessionTests {
  @Test("Fresh launch selects the provided Home Folder")
  func freshLaunchSelectsHomeFolder() {
    let homeDirectoryURL = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    let session = ExplorerSession(homeDirectoryURL: homeDirectoryURL)

    #expect(session.selectedScope == .homeFolder(homeDirectoryURL))
  }

  @Test("Fresh launch remains idle until an explicit scan")
  func freshLaunchRemainsIdle() {
    let homeDirectoryURL = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    let session = ExplorerSession(homeDirectoryURL: homeDirectoryURL)

    #expect(session.scanState == .idle)
  }
}
