import Foundation

@MainActor
struct AppContainer {
  let explorerSession: ExplorerSession
  let customScopeChooser: any CustomScopeChoosing
  let systemSettingsOpener: any SystemSettingsOpening

  init(
    homeDirectoryURL: URL,
    scanner: any FileSystemScanning,
    snapshotIndex: any ScanSnapshotIndexing,
    scopeAuthorizer: (any ScanScopeAuthorizing)? = nil,
    customScopeBookmarkStore: (any CustomScopeBookmarking)? = nil,
    customScopeChooser: any CustomScopeChoosing = NativeCustomScopePicker(),
    systemSettingsOpener: any SystemSettingsOpening = PrivacySystemSettingsOpener()
  ) {
    explorerSession = ExplorerSession(
      homeDirectoryURL: homeDirectoryURL,
      scanner: scanner,
      snapshotIndex: snapshotIndex,
      scopeAuthorizer: scopeAuthorizer,
      customScopeBookmarkStore: customScopeBookmarkStore
    )
    self.customScopeChooser = customScopeChooser
    self.systemSettingsOpener = systemSettingsOpener
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
      scopeAuthorizer: scopeAuthorizer,
      customScopeBookmarkStore: bookmarkStore
    )
  }
}
