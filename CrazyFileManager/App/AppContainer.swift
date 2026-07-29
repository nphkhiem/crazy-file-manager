import Foundation

@MainActor
struct AppContainer {
  let explorerSession: ExplorerSession

  init(
    homeDirectoryURL: URL,
    scanner: any FileSystemScanning,
    snapshotIndex: any ScanSnapshotIndexing
  ) {
    explorerSession = ExplorerSession(
      homeDirectoryURL: homeDirectoryURL,
      scanner: scanner,
      snapshotIndex: snapshotIndex
    )
  }

  static func live() -> Self {
    let snapshotDatabaseURL = URL.applicationSupportDirectory
      .appending(
        path: "Crazy File Manager",
        directoryHint: .isDirectory
      )
      .appending(path: "ScanSnapshot.sqlite")
    return Self(
      homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
      scanner: FoundationFileSystemScanner(),
      snapshotIndex: SQLiteScanSnapshotIndex(
        databaseURL: snapshotDatabaseURL
      )
    )
  }
}
