import CryptoKit
import Foundation

@MainActor
struct AppContainer {
  let explorerSession: ExplorerSession
  let updateCheckSession: UpdateCheckSession
  let customScopeChooser: any CustomScopeChoosing
  let systemSettingsOpener: any SystemSettingsOpening

  init(
    homeDirectoryURL: URL,
    scanner: any FileSystemScanning,
    snapshotIndex: any ScanSnapshotIndexing,
    scopeAuthorizer: (any ScanScopeAuthorizing)? = nil,
    customScopeBookmarkStore: (any CustomScopeBookmarking)? = nil,
    dateProvider: any DateProviding = SystemDateProvider(),
    customScopeChooser: any CustomScopeChoosing = NativeCustomScopePicker(),
    systemSettingsOpener: any SystemSettingsOpening = PrivacySystemSettingsOpener(),
    updateClient: any UpdateChecking = FoundationUpdateClient(),
    updateArtifactDownloader: any UpdateArtifactDownloading = FoundationUpdateArtifactDownloader(),
    updateCheckPreferencesStore: any UpdateCheckPreferencesStoring =
      UserDefaultsUpdateCheckPreferencesStore(),
    downloadedFileRevealer: any DownloadedFileRevealing = WorkspaceDownloadedFileRevealer(),
    updateMetadataURL: URL = UpdateCheckConfiguration.metadataURL,
    updateSigningPublicKeyBase64: String = UpdateSigningKey.pinnedPublicKeyBase64,
    installedVersion: AppVersion = AppContainer.liveInstalledVersion(),
    currentSystemVersion: AppVersion = AppContainer.liveCurrentSystemVersion()
  ) {
    explorerSession = ExplorerSession(
      homeDirectoryURL: homeDirectoryURL,
      scanner: scanner,
      snapshotIndex: snapshotIndex,
      scopeAuthorizer: scopeAuthorizer,
      customScopeBookmarkStore: customScopeBookmarkStore,
      dateProvider: dateProvider
    )
    updateCheckSession = UpdateCheckSession(
      updateClient: updateClient,
      downloader: updateArtifactDownloader,
      preferencesStore: updateCheckPreferencesStore,
      fileRevealer: downloadedFileRevealer,
      metadataURL: updateMetadataURL,
      publicKeyBase64: updateSigningPublicKeyBase64,
      installedVersion: installedVersion,
      currentSystemVersion: currentSystemVersion
    )
    self.customScopeChooser = customScopeChooser
    self.systemSettingsOpener = systemSettingsOpener
  }

  static func liveInstalledVersion() -> AppVersion {
    let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    return raw.flatMap(AppVersion.init) ?? AppVersion("0.0.0")!
  }

  static func liveCurrentSystemVersion() -> AppVersion {
    let systemVersion = ProcessInfo.processInfo.operatingSystemVersion
    return AppVersion(
      "\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)"
    )!
  }

  static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self {
    #if DEBUG
      if let scenario = DebugLaunchScenario(arguments: arguments) {
        return debug(scenario: scenario)
      }
    #endif
    let snapshotDatabaseURL = URL.applicationSupportDirectory
      .appending(
        path: "Crazy File Manager",
        directoryHint: .isDirectory
      )
      .appending(path: "ScanSnapshot.sqlite")
    let homeDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    let bookmarkStore = FoundationCustomScopeBookmarkStore()
    let dateProvider = SystemDateProvider()
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
        databaseURL: snapshotDatabaseURL,
        dateProvider: dateProvider
      ),
      scopeAuthorizer: scopeAuthorizer,
      customScopeBookmarkStore: bookmarkStore,
      dateProvider: dateProvider
    )
  }
}

#if DEBUG
  extension AppContainer {
    fileprivate static func debug(scenario: DebugLaunchScenario) -> Self {
      let homeDirectoryURL = URL(
        filePath: "/Users/debugger",
        directoryHint: .isDirectory
      )
      return Self(
        homeDirectoryURL: homeDirectoryURL,
        scanner: DebugScenarioFileSystemScanner(),
        snapshotIndex: DebugScenarioSnapshotIndex(
          preparation: scenario.preparation,
          clearFails: scenario.clearFails
        ),
        updateClient: DebugUpdateChecking(),
        updateArtifactDownloader: DebugUpdateArtifactDownloading(),
        updateCheckPreferencesStore: UserDefaultsUpdateCheckPreferencesStore(
          defaults: UserDefaults(suiteName: "com.nphkhiem.CrazyFileManager.debug")!
        ),
        downloadedFileRevealer: DebugDownloadedFileRevealing(),
        updateMetadataURL: URL(string: "https://example.com/update-metadata.json")!,
        updateSigningPublicKeyBase64: DebugUpdateFixture.publicKeyBase64,
        installedVersion: DebugUpdateFixture.installedVersion,
        currentSystemVersion: AppVersion("99.0.0")!
      )
    }
  }

  private enum DebugLaunchScenario {
    case empty
    case cachedResults
    case cachedResultsClearFailure
    case cachedResultsRenameEligible
    case trashEligible
    case bulkTrashEligible
    case allItemsEligible
    case expiredResults
    case largeKeyboardTraversal

    init?(arguments: [String]) {
      guard
        let scenarioIndex = arguments.firstIndex(of: "-uiScenario"),
        arguments.indices.contains(arguments.index(after: scenarioIndex))
      else {
        return nil
      }
      switch arguments[arguments.index(after: scenarioIndex)] {
      case "empty":
        self = .empty
      case "cachedResults":
        self = .cachedResults
      case "cachedResultsClearFailure":
        self = .cachedResultsClearFailure
      case "cachedResultsRenameEligible":
        self = .cachedResultsRenameEligible
      case "trashEligible":
        self = .trashEligible
      case "bulkTrashEligible":
        self = .bulkTrashEligible
      case "allItemsEligible":
        self = .allItemsEligible
      case "expiredResults":
        self = .expiredResults
      case "largeKeyboardTraversal":
        self = .largeKeyboardTraversal
      default:
        return nil
      }
    }

    var preparation: ScanCachePreparation {
      let scope = ScanScope(
        kind: .homeFolder,
        location: URL(filePath: "/Users/debugger", directoryHint: .isDirectory),
        volumeIdentity: ScanVolumeIdentity(rawValue: "DEBUG-HOME"),
        volumeCharacteristics: ScanVolumeCharacteristics(
          isInternal: true,
          isReadOnly: false,
          isRemovable: false
        )
      )
      switch self {
      case .empty:
        return .empty
      case .cachedResults, .cachedResultsClearFailure:
        let completedAt = Date(timeIntervalSince1970: 1_785_578_400)
        let root = StorageTreeItem(
          id: UUID(),
          parentID: nil,
          location: scope.location,
          name: "debugger",
          kind: .folder,
          diskUsedBytes: 0,
          apparentSizeBytes: 0,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: false,
          isRoot: true
        )
        return .available(
          CachedScanSnapshot(
            scanID: ScanID(rawValue: UUID()),
            scope: scope,
            completion: ScanCompletion(accessibleItemCount: 0, issueCount: 0),
            completedAt: completedAt,
            expiresAt: completedAt.addingTimeInterval(86_400),
            largestItems: [],
            treeRoot: root,
            rootPage: StorageTreePage(
              parentID: root.id,
              items: [],
              nextOffset: nil
            )
          )
        )
      case .cachedResultsRenameEligible:
        let completedAt = Date(timeIntervalSince1970: 1_785_578_400)
        let renameEligibleRoot = Self.makeRenameEligibleFixtureDirectory()
        let renameEligibleScope = ScanScope(
          kind: scope.kind,
          location: renameEligibleRoot,
          volumeIdentity: scope.volumeIdentity,
          volumeCharacteristics: scope.volumeCharacteristics
        )
        let root = StorageTreeItem(
          id: UUID(),
          parentID: nil,
          location: renameEligibleRoot,
          name: "debugger",
          kind: .folder,
          diskUsedBytes: 10,
          apparentSizeBytes: 10,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: true,
          isRoot: true
        )
        let child = StorageTreeItem(
          id: UUID(),
          parentID: root.id,
          location: renameEligibleRoot.appending(path: "notes.txt"),
          name: "notes.txt",
          kind: .file,
          diskUsedBytes: 10,
          apparentSizeBytes: 10,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: false,
          isRoot: false
        )
        return .available(
          CachedScanSnapshot(
            scanID: ScanID(rawValue: UUID()),
            scope: renameEligibleScope,
            completion: ScanCompletion(accessibleItemCount: 1, issueCount: 0),
            completedAt: completedAt,
            expiresAt: completedAt.addingTimeInterval(86_400),
            largestItems: [],
            treeRoot: root,
            rootPage: StorageTreePage(
              parentID: root.id,
              items: [child],
              nextOffset: nil
            )
          )
        )
      case .largeKeyboardTraversal:
        let completedAt = Date(timeIntervalSince1970: 1_785_578_400)
        let largeTraversalRoot = Self.makeLargeKeyboardTraversalFixtureDirectory(
          itemCount: 300
        )
        let largeTraversalScope = ScanScope(
          kind: scope.kind,
          location: largeTraversalRoot,
          volumeIdentity: scope.volumeIdentity,
          volumeCharacteristics: scope.volumeCharacteristics
        )
        let itemCount = 300
        let root = StorageTreeItem(
          id: UUID(),
          parentID: nil,
          location: largeTraversalRoot,
          name: "debugger",
          kind: .folder,
          diskUsedBytes: Int64(itemCount) * 10,
          apparentSizeBytes: Int64(itemCount) * 10,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: true,
          isRoot: true
        )
        let children = (0..<itemCount).map { index in
          StorageTreeItem(
            id: UUID(),
            parentID: root.id,
            location: largeTraversalRoot.appending(
              path: String(format: "item-%04d.bin", index)
            ),
            name: String(format: "item-%04d.bin", index),
            kind: .file,
            diskUsedBytes: 10,
            apparentSizeBytes: 10,
            isDiskUsedIncomplete: false,
            isApparentSizeIncomplete: false,
            hasChildren: false,
            isRoot: false
          )
        }
        return .available(
          CachedScanSnapshot(
            scanID: ScanID(rawValue: UUID()),
            scope: largeTraversalScope,
            completion: ScanCompletion(accessibleItemCount: itemCount, issueCount: 0),
            completedAt: completedAt,
            expiresAt: completedAt.addingTimeInterval(86_400),
            largestItems: [],
            treeRoot: root,
            rootPage: StorageTreePage(
              parentID: root.id,
              items: children,
              nextOffset: nil
            )
          )
        )
      case .trashEligible:
        let completedAt = Date(timeIntervalSince1970: 1_785_578_400)
        let trashEligibleRoot = Self.makeTrashEligibleFixtureDirectory()
        let trashEligibleScope = ScanScope(
          kind: scope.kind,
          location: trashEligibleRoot,
          volumeIdentity: scope.volumeIdentity,
          volumeCharacteristics: scope.volumeCharacteristics
        )
        let root = StorageTreeItem(
          id: UUID(),
          parentID: nil,
          location: trashEligibleRoot,
          name: "debugger",
          kind: .folder,
          diskUsedBytes: 10,
          apparentSizeBytes: 10,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: true,
          isRoot: true
        )
        let child = StorageTreeItem(
          id: UUID(),
          parentID: root.id,
          location: trashEligibleRoot.appending(path: "notes.txt"),
          name: "notes.txt",
          kind: .file,
          diskUsedBytes: 10,
          apparentSizeBytes: 10,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: false,
          isRoot: false
        )
        return .available(
          CachedScanSnapshot(
            scanID: ScanID(rawValue: UUID()),
            scope: trashEligibleScope,
            completion: ScanCompletion(accessibleItemCount: 1, issueCount: 0),
            completedAt: completedAt,
            expiresAt: completedAt.addingTimeInterval(86_400),
            largestItems: [],
            treeRoot: root,
            rootPage: StorageTreePage(
              parentID: root.id,
              items: [child],
              nextOffset: nil
            )
          )
        )
      case .bulkTrashEligible:
        let completedAt = Date(timeIntervalSince1970: 1_785_578_400)
        let bulkTrashEligibleRoot = Self.makeBulkTrashEligibleFixtureDirectory()
        let bulkTrashEligibleScope = ScanScope(
          kind: scope.kind,
          location: bulkTrashEligibleRoot,
          volumeIdentity: scope.volumeIdentity,
          volumeCharacteristics: scope.volumeCharacteristics
        )
        let root = StorageTreeItem(
          id: UUID(),
          parentID: nil,
          location: bulkTrashEligibleRoot,
          name: "debugger",
          kind: .folder,
          diskUsedBytes: 20,
          apparentSizeBytes: 20,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: true,
          isRoot: true
        )
        let first = StorageTreeItem(
          id: UUID(),
          parentID: root.id,
          location: bulkTrashEligibleRoot.appending(path: "first.txt"),
          name: "first.txt",
          kind: .file,
          diskUsedBytes: 10,
          apparentSizeBytes: 10,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: false,
          isRoot: false
        )
        let second = StorageTreeItem(
          id: UUID(),
          parentID: root.id,
          location: bulkTrashEligibleRoot.appending(path: "second.txt"),
          name: "second.txt",
          kind: .file,
          diskUsedBytes: 10,
          apparentSizeBytes: 10,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: false,
          isRoot: false
        )
        return .available(
          CachedScanSnapshot(
            scanID: ScanID(rawValue: UUID()),
            scope: bulkTrashEligibleScope,
            completion: ScanCompletion(accessibleItemCount: 2, issueCount: 0),
            completedAt: completedAt,
            expiresAt: completedAt.addingTimeInterval(86_400),
            largestItems: [],
            treeRoot: root,
            rootPage: StorageTreePage(
              parentID: root.id,
              items: [first, second],
              nextOffset: nil
            )
          )
        )
      case .allItemsEligible:
        let completedAt = Date(timeIntervalSince1970: 1_785_578_400)
        let allItemsEligibleRoot = Self.makeAllItemsEligibleFixtureDirectory()
        let allItemsEligibleScope = ScanScope(
          kind: scope.kind,
          location: allItemsEligibleRoot,
          volumeIdentity: scope.volumeIdentity,
          volumeCharacteristics: scope.volumeCharacteristics
        )
        let root = StorageTreeItem(
          id: UUID(),
          parentID: nil,
          location: allItemsEligibleRoot,
          name: "debugger",
          kind: .folder,
          diskUsedBytes: 43,
          apparentSizeBytes: 43,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: true,
          isRoot: true
        )
        let visible = StorageTreeItem(
          id: UUID(),
          parentID: root.id,
          location: allItemsEligibleRoot.appending(path: "visible.txt"),
          name: "visible.txt",
          kind: .file,
          diskUsedBytes: 10,
          apparentSizeBytes: 10,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: false,
          isRoot: false
        )
        let hidden = StorageTreeItem(
          id: UUID(),
          parentID: root.id,
          location: allItemsEligibleRoot.appending(path: ".hidden.txt"),
          name: ".hidden.txt",
          kind: .file,
          diskUsedBytes: 5,
          apparentSizeBytes: 5,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: false,
          isRoot: false,
          isHidden: true
        )
        let documents = StorageTreeItem(
          id: UUID(),
          parentID: root.id,
          location: allItemsEligibleRoot.appending(path: "Documents", directoryHint: .isDirectory),
          name: "Documents",
          kind: .folder,
          diskUsedBytes: 20,
          apparentSizeBytes: 20,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: false,
          isRoot: false
        )
        let cloud = StorageTreeItem(
          id: UUID(),
          parentID: root.id,
          location: allItemsEligibleRoot.appending(path: "cloud.txt"),
          name: "cloud.txt",
          kind: .file,
          diskUsedBytes: 8,
          apparentSizeBytes: 8,
          isDiskUsedIncomplete: false,
          isApparentSizeIncomplete: false,
          hasChildren: false,
          isRoot: false,
          isCloudOnly: true
        )
        return .available(
          CachedScanSnapshot(
            scanID: ScanID(rawValue: UUID()),
            scope: allItemsEligibleScope,
            completion: ScanCompletion(accessibleItemCount: 4, issueCount: 0),
            completedAt: completedAt,
            expiresAt: completedAt.addingTimeInterval(86_400),
            largestItems: [],
            treeRoot: root,
            rootPage: StorageTreePage(
              parentID: root.id,
              items: [visible, hidden, documents, cloud],
              nextOffset: nil
            )
          )
        )
      case .expiredResults:
        return .expired(
          previousScope: scope,
          completedAt: Date(timeIntervalSince1970: 1_785_578_400)
        )
      }
    }

    var clearFails: Bool {
      self == .cachedResultsClearFailure
    }

    private static func makeLargeKeyboardTraversalFixtureDirectory(itemCount: Int) -> URL {
      let directory = FileManager.default.temporaryDirectory
        .appending(
          path: "CrazyFileManagerUITests-LargeKeyboardTraversal",
          directoryHint: .isDirectory
        )
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      for index in 0..<itemCount {
        let name = String(format: "item-%04d.bin", index)
        try? Data("x".utf8).write(to: directory.appending(path: name))
      }
      return directory
    }

    private static func makeRenameEligibleFixtureDirectory() -> URL {
      let directory = FileManager.default.temporaryDirectory
        .appending(path: "CrazyFileManagerUITests-RenameEligible", directoryHint: .isDirectory)
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      try? Data("Sample notes.".utf8).write(to: directory.appending(path: "notes.txt"))
      return directory
    }

    private static func makeTrashEligibleFixtureDirectory() -> URL {
      let directory = FileManager.default.temporaryDirectory
        .appending(path: "CrazyFileManagerUITests-TrashEligible", directoryHint: .isDirectory)
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      try? Data("Sample notes.".utf8).write(to: directory.appending(path: "notes.txt"))
      return directory
    }

    private static func makeBulkTrashEligibleFixtureDirectory() -> URL {
      let directory = FileManager.default.temporaryDirectory
        .appending(
          path: "CrazyFileManagerUITests-BulkTrashEligible",
          directoryHint: .isDirectory
        )
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      try? Data("First.".utf8).write(to: directory.appending(path: "first.txt"))
      try? Data("Second.".utf8).write(to: directory.appending(path: "second.txt"))
      return directory
    }

    private static func makeAllItemsEligibleFixtureDirectory() -> URL {
      let directory = FileManager.default.temporaryDirectory
        .appending(
          path: "CrazyFileManagerUITests-AllItemsEligible",
          directoryHint: .isDirectory
        )
      try? FileManager.default.removeItem(at: directory)
      try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      try? Data("Visible.".utf8).write(to: directory.appending(path: "visible.txt"))
      try? Data("Hidden.".utf8).write(to: directory.appending(path: ".hidden.txt"))
      try? FileManager.default.createDirectory(
        at: directory.appending(path: "Documents", directoryHint: .isDirectory),
        withIntermediateDirectories: true
      )
      try? Data("Cloud.".utf8).write(to: directory.appending(path: "cloud.txt"))
      return directory
    }
  }

  private enum DebugUpdateFixture {
    static let signingKey = Curve25519.Signing.PrivateKey()
    static let installedVersion = AppVersion("1.0.0")!
    static let metadata = UpdateMetadata(
      formatVersion: UpdateMetadataVerifier.supportedFormatVersion,
      version: "2.0.0",
      minimumSystemVersion: "13.0.0",
      downloadURL: URL(string: "https://example.com/CrazyFileManager-debug.dmg")!,
      releaseNotesURL: nil
    )

    static var publicKeyBase64: String {
      signingKey.publicKey.rawRepresentation.base64EncodedString()
    }

    static func signedEnvelope() throws -> Data {
      let payloadBytes = try JSONEncoder().encode(metadata)
      let signature = try signingKey.signature(for: payloadBytes)
      let envelope: [String: String] = [
        "payload": payloadBytes.base64EncodedString(),
        "signature": signature.base64EncodedString(),
      ]
      return try JSONSerialization.data(withJSONObject: envelope)
    }
  }

  private struct DebugUpdateChecking: UpdateChecking {
    func fetchMetadataEnvelope(from url: URL) async throws -> Data {
      try DebugUpdateFixture.signedEnvelope()
    }
  }

  private struct DebugUpdateArtifactDownloading: UpdateArtifactDownloading {
    func download(from url: URL) async throws -> URL {
      URL(filePath: "/tmp/CrazyFileManager-debug-update.dmg")
    }
  }

  private struct DebugDownloadedFileRevealing: DownloadedFileRevealing {
    func reveal(_ fileURL: URL) {}
  }

  private struct DebugScenarioFileSystemScanner: FileSystemScanning {
    func batches(
      for scope: ScanScope
    ) async -> AsyncThrowingStream<FileSystemScanBatch, Error> {
      AsyncThrowingStream { continuation in
        continuation.finish()
      }
    }
  }

  private actor DebugScenarioSnapshotIndex: ScanSnapshotIndexing {
    private let preparation: ScanCachePreparation
    private let clearFails: Bool
    private var isCleared = false

    init(
      preparation: ScanCachePreparation,
      clearFails: Bool
    ) {
      self.preparation = preparation
      self.clearFails = clearFails
    }

    func removeCrashLeftoverCandidates() {}

    func prepareCacheForLaunch(
      largestItemLimit: Int,
      treePageLimit: Int
    ) -> ScanCachePreparation {
      preparation
    }

    func refreshCompletedCache(
      largestItemLimit: Int,
      treePageLimit: Int
    ) -> ScanCachePreparation {
      .empty
    }

    func clearCompletedSnapshot() throws {
      if clearFails {
        throw SnapshotIndexError.statementFailed(code: 1)
      }
      isCleared = true
    }

    func beginCandidate(for scope: ScanScope) throws -> ScanID {
      throw SnapshotIndexError.candidateNotFound
    }

    func append(
      _ batch: FileSystemScanBatch,
      to candidate: ScanID
    ) throws {
      throw SnapshotIndexError.candidateNotFound
    }

    func largestItems(
      in candidate: ScanID,
      limit: Int
    ) throws -> [StorageItemSummary] {
      throw SnapshotIndexError.candidateNotFound
    }

    func treeRoot(in scan: ScanID) throws -> StorageTreeItem {
      throw SnapshotIndexError.candidateNotFound
    }

    func itemDetail(for itemID: UUID, in scan: ScanID) throws -> StorageItemDetail? {
      guard case .available(let snapshot) = preparation else {
        throw SnapshotIndexError.candidateNotFound
      }
      let items = [snapshot.treeRoot] + snapshot.rootPage.items
      guard let item = items.first(where: { $0.id == itemID }) else {
        return nil
      }
      return StorageItemDetail(
        item: item,
        volumeCharacteristics: snapshot.scope.volumeCharacteristics
      )
    }

    func updateItemName(
      _ itemID: UUID,
      in scan: ScanID,
      newName: String,
      newPath: String
    ) throws {
      throw SnapshotIndexError.candidateNotFound
    }

    func descendantCount(of itemID: UUID, in scan: ScanID) throws -> Int? {
      throw SnapshotIndexError.candidateNotFound
    }

    func removeItem(_ itemID: UUID, in scan: ScanID) throws {
      throw SnapshotIndexError.candidateNotFound
    }

    func issues(in scan: ScanID, limit: Int) throws -> [ScanIssue] {
      throw SnapshotIndexError.candidateNotFound
    }

    func directChildren(
      of parentID: UUID,
      in scan: ScanID,
      offset: Int,
      limit: Int
    ) throws -> StorageTreePage {
      throw SnapshotIndexError.candidateNotFound
    }

    func flatItems(
      in scan: ScanID,
      query: AllItemsQuery,
      offset: Int,
      limit: Int
    ) throws -> AllItemsPage {
      guard case .available(let snapshot) = preparation else {
        throw SnapshotIndexError.candidateNotFound
      }
      let matches = query.applying(to: snapshot.rootPage.items)
      let boundedOffset = min(max(0, offset), matches.count)
      let boundedLimit = max(0, limit)
      let end = min(boundedOffset + boundedLimit, matches.count)
      return AllItemsPage(
        items: Array(matches[boundedOffset..<end]),
        nextOffset: end < matches.count ? end : nil
      )
    }

    func promoteCandidate(
      _ candidate: ScanID,
      expectedItemCount: Int,
      expectedIssueCount: Int,
      largestItemLimit: Int,
      treePageLimit: Int
    ) throws -> PromotedScanSnapshot {
      throw SnapshotIndexError.candidateNotFound
    }

    func discardCandidate(_ candidate: ScanID) throws {
      throw SnapshotIndexError.candidateNotFound
    }

    func cacheFileSizeBytes() -> Int64? {
      isCleared ? nil : 2_400_000
    }
  }
#endif
