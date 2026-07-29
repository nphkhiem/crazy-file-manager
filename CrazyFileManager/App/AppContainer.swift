import Foundation

@MainActor
struct AppContainer {
  let explorerSession: ExplorerSession

  init(homeDirectoryURL: URL) {
    explorerSession = ExplorerSession(homeDirectoryURL: homeDirectoryURL)
  }

  static func live() -> Self {
    Self(homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser)
  }
}
