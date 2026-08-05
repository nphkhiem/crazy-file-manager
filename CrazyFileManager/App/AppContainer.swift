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
    case cachedResultsRenameEligible
    case trashEligible
    case bulkTrashEligible
    case allItemsEligible
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
      let searchText = query.searchText.lowercased()
      let matches = snapshot.rootPage.items.filter { item in
        if !query.filters.kinds.isEmpty, !query.filters.kinds.contains(item.kind) {
          return false
        }
        switch query.filters.hidden {
        case .any: break
        case .onlyTrue: if !item.isHidden { return false }
        case .onlyFalse: if item.isHidden { return false }
        }
        switch query.filters.cloudOnly {
        case .any: break
        case .onlyTrue: if !item.isCloudOnly { return false }
        case .onlyFalse: if item.isCloudOnly { return false }
        }
        if let minimum = query.filters.minimumDiskUsedBytes, (item.diskUsedBytes ?? -1) < minimum {
          return false
        }
        if !searchText.isEmpty {
          let name = item.name.lowercased()
          let path = item.location.path(percentEncoded: false).lowercased()
          if !name.contains(searchText), !path.contains(searchText) {
            return false
          }
        }
        return true
      }
      .sorted { Self.flatItemsSortsBefore($0, $1, sort: query.sort) }
      let boundedOffset = min(max(0, offset), matches.count)
      let boundedLimit = max(0, limit)
      let end = min(boundedOffset + boundedLimit, matches.count)
      return AllItemsPage(
        items: Array(matches[boundedOffset..<end]),
        nextOffset: end < matches.count ? end : nil
      )
    }

    private static func flatItemsSortsBefore(
      _ lhs: StorageTreeItem,
      _ rhs: StorageTreeItem,
      sort: AllItemsSort
    ) -> Bool {
      func compare<Value: Comparable>(_ lhsValue: Value?, _ rhsValue: Value?) -> Bool? {
        switch (lhsValue, rhsValue) {
        case (.some(let a), .some(let b)):
          guard a != b else { return nil }
          return sort.direction == .ascending ? a < b : a > b
        case (.some, .none):
          return true
        case (.none, .some):
          return false
        case (.none, .none):
          return nil
        }
      }

      let primary: Bool?
      switch sort.field {
      case .diskUsed:
        primary = compare(lhs.diskUsedBytes, rhs.diskUsedBytes)
      case .apparentSize:
        primary = compare(lhs.apparentSizeBytes, rhs.apparentSizeBytes)
      case .name:
        primary = compare(lhs.name, rhs.name)
      case .modifiedAt:
        primary = compare(lhs.modifiedAt, rhs.modifiedAt)
      case .path:
        primary = compare(
          lhs.location.path(percentEncoded: false),
          rhs.location.path(percentEncoded: false)
        )
      }
      if let primary {
        return primary
      }
      return lhs.id.uuidString < rhs.id.uuidString
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
