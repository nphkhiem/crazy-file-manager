import Foundation

@MainActor
struct AppContainer {
  let explorerSession: ExplorerSession

  init(
    homeDirectoryURL: URL,
    scanner: any FileSystemScanning,
    snapshotIndex: any ScanSnapshotIndexing,
    scopeAuthorizer: (any ScanScopeAuthorizing)? = nil
  ) {
    explorerSession = ExplorerSession(
      homeDirectoryURL: homeDirectoryURL,
      scanner: scanner,
      snapshotIndex: snapshotIndex,
      scopeAuthorizer: scopeAuthorizer
    )
  }

  static func live() -> Self {
    let snapshotDatabaseURL = URL.applicationSupportDirectory
      .appending(
        path: "Crazy File Manager",
        directoryHint: .isDirectory
      )
      .appending(path: "ScanSnapshot.sqlite")
    let homeDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    let bookmarkStore = FoundationCustomScopeBookmarkStore()
    let scopeAuthorizer = FoundationScanScopeAuthorizer(
      homeDirectoryURL: homeDirectoryURL,
      internalDiskURL: URL(filePath: "/", directoryHint: .isDirectory),
      resourceReader: FoundationScanScopeResourceReader(),
      bookmarkResolver: bookmarkStore
    )
    return Self(
      homeDirectoryURL: homeDirectoryURL,
      scanner: FoundationFileSystemScanner(),
      snapshotIndex: SQLiteScanSnapshotIndex(
        databaseURL: snapshotDatabaseURL
      ),
      scopeAuthorizer: scopeAuthorizer
    )
  }
}
