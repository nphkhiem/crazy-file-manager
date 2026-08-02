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
    dateProvider: any DateProviding = SystemDateProvider(),
    customScopeChooser: any CustomScopeChoosing = NativeCustomScopePicker(),
    systemSettingsOpener: any SystemSettingsOpening = PrivacySystemSettingsOpener()
  ) {
    explorerSession = ExplorerSession(
      homeDirectoryURL: homeDirectoryURL,
      scanner: scanner,
      snapshotIndex: snapshotIndex,
      scopeAuthorizer: scopeAuthorizer,
      customScopeBookmarkStore: customScopeBookmarkStore,
      dateProvider: dateProvider
    )
    self.customScopeChooser = customScopeChooser
    self.systemSettingsOpener = systemSettingsOpener
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
        )
      )
    }
  }

  private enum DebugLaunchScenario {
    case empty
    case cachedResults
    case cachedResultsClearFailure
    case expiredResults

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
      case "expiredResults":
        self = .expiredResults
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
      throw SnapshotIndexError.candidateNotFound
    }

    func updateItemName(
      _ itemID: UUID,
      in scan: ScanID,
      newName: String,
      newPath: String
    ) throws {
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
  }
#endif
