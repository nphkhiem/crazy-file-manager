import Foundation

@testable import CrazyFileManager

actor InMemoryScanSnapshotIndex: ScanSnapshotIndexing {
  private struct TreeConfiguration: Sendable {
    let root: StorageTreeItem
    let children: [UUID: [StorageTreeItem]]
  }

  private struct Snapshot: Sendable {
    let scope: ScanScope
    var items: [ScannedItem] = []
    var issues: [ScanIssue] = []
    var treeRoot: StorageTreeItem
    var treeChildren: [UUID: [StorageTreeItem]]
  }

  private let configuredTreeRoot: StorageTreeItem?
  private let configuredTreeChildren: [UUID: [StorageTreeItem]]
  private let dateProvider: any DateProviding
  private var treeFailuresRemaining: [UUID: Int]
  private var candidates: [ScanID: Snapshot] = [:]
  private var completedSnapshots: [ScanID: Snapshot] = [:]
  private var completedCacheSnapshot: CachedScanSnapshot?
  private var queuedTreeConfigurations: [TreeConfiguration] = []
  private var blocksNextLaunchPreparation = false
  private(set) var isLaunchPreparationBlocked = false
  private var launchPreparationContinuation: CheckedContinuation<Void, Never>?
  private var blocksNextPromotion = false
  private(set) var isPromotionBlocked = false
  private var promotionContinuation: CheckedContinuation<Void, Never>?
  private var failsNextPromotionPresentation = false
  private var failsNextCandidateDiscard = false
  private var failsNextItemDetail = false
  private var blocksNextFlatItems = false
  private(set) var isFlatItemsBlocked = false
  private var flatItemsContinuation: CheckedContinuation<Void, Never>?
  private(set) var flatItemsCallCount = 0
  private var queuedLaunchPreparations: [Result<ScanCachePreparation, SnapshotIndexError>] = []
  private var queuedRefreshPreparations: [Result<ScanCachePreparation, SnapshotIndexError>] = []
  private var clearCompletedSnapshotError: SnapshotIndexError?
  private var configuredCacheFileSizeBytes: Int64?
  private(set) var lifecycleEvents: [String] = []
  private(set) var requestedScopes: [ScanScope] = []

  init(
    treeRoot: StorageTreeItem? = nil,
    treeChildren: [UUID: [StorageTreeItem]] = [:],
    failingTreeParentIDs: Set<UUID> = [],
    dateProvider: any DateProviding = SystemDateProvider()
  ) {
    configuredTreeRoot = treeRoot
    configuredTreeChildren = treeChildren
    self.dateProvider = dateProvider
    treeFailuresRemaining = [:]
    for parentID in failingTreeParentIDs {
      treeFailuresRemaining[parentID] = .max
    }
  }

  var candidateCount: Int {
    candidates.count
  }

  func removeCrashLeftoverCandidates() {
    candidates.removeAll()
    lifecycleEvents.append("cleanup")
  }

  func prepareCacheForLaunch(
    largestItemLimit: Int,
    treePageLimit: Int
  ) async throws -> ScanCachePreparation {
    candidates.removeAll()
    lifecycleEvents.append("cleanup")
    if blocksNextLaunchPreparation {
      blocksNextLaunchPreparation = false
      isLaunchPreparationBlocked = true
      await withCheckedContinuation { continuation in
        launchPreparationContinuation = continuation
      }
      isLaunchPreparationBlocked = false
    }
    guard !queuedLaunchPreparations.isEmpty else {
      return .empty
    }
    return try queuedLaunchPreparations.removeFirst().get()
  }

  func refreshCompletedCache(
    largestItemLimit: Int,
    treePageLimit: Int
  ) throws -> ScanCachePreparation {
    guard !queuedRefreshPreparations.isEmpty else {
      return .empty
    }
    return try queuedRefreshPreparations.removeFirst().get()
  }

  func clearCompletedSnapshot() throws {
    if let clearCompletedSnapshotError {
      self.clearCompletedSnapshotError = nil
      throw clearCompletedSnapshotError
    }
    completedSnapshots.removeAll()
    completedCacheSnapshot = nil
    lifecycleEvents.append("clear")
  }

  func cachedSnapshot() throws -> CachedScanSnapshot {
    guard let completedCacheSnapshot else {
      throw SnapshotIndexError.candidateNotFound
    }
    return completedCacheSnapshot
  }

  func enqueueLaunchPreparation(
    _ result: Result<ScanCachePreparation, SnapshotIndexError>
  ) {
    queuedLaunchPreparations.append(result)
  }

  func enqueueRefreshPreparation(
    _ result: Result<ScanCachePreparation, SnapshotIndexError>
  ) {
    queuedRefreshPreparations.append(result)
  }

  func failNextClearCompletedSnapshot(
    with error: SnapshotIndexError = .statementFailed(code: 1)
  ) {
    clearCompletedSnapshotError = error
  }

  func enqueueTreeSnapshot(
    root: StorageTreeItem,
    children: [UUID: [StorageTreeItem]]
  ) {
    queuedTreeConfigurations.append(
      TreeConfiguration(root: root, children: children)
    )
  }

  func blockNextLaunchPreparation() {
    blocksNextLaunchPreparation = true
  }

  func unblockLaunchPreparation() {
    launchPreparationContinuation?.resume()
    launchPreparationContinuation = nil
  }

  func blockNextPromotion() {
    blocksNextPromotion = true
  }

  func unblockPromotion() {
    promotionContinuation?.resume()
    promotionContinuation = nil
  }

  func failNextPromotionPresentation() {
    failsNextPromotionPresentation = true
  }

  func failNextCandidateDiscard() {
    failsNextCandidateDiscard = true
  }

  func failNextTreePage(for parentID: UUID) {
    treeFailuresRemaining[parentID] = 1
  }

  func failNextItemDetail() {
    failsNextItemDetail = true
  }

  func blockNextFlatItems() {
    blocksNextFlatItems = true
  }

  func unblockFlatItems() {
    flatItemsContinuation?.resume()
    flatItemsContinuation = nil
  }

  func remainingTreeFailureCount(for parentID: UUID) -> Int {
    treeFailuresRemaining[parentID] ?? 0
  }

  func beginCandidate(for scope: ScanScope) async throws -> ScanID {
    requestedScopes.append(scope)
    let candidate = ScanID(rawValue: UUID())
    let queuedConfiguration =
      queuedTreeConfigurations.isEmpty
      ? nil
      : queuedTreeConfigurations.removeFirst()
    let root =
      queuedConfiguration?.root
      ?? configuredTreeRoot
      ?? StorageTreeItem(
        id: UUID(),
        parentID: nil,
        location: scope.location,
        name: scope.location.lastPathComponent,
        kind: .folder,
        diskUsedBytes: nil,
        apparentSizeBytes: nil,
        isDiskUsedIncomplete: false,
        isApparentSizeIncomplete: false,
        hasChildren: false,
        isRoot: true
      )
    candidates[candidate] = Snapshot(
      scope: scope,
      treeRoot: root,
      treeChildren:
        queuedConfiguration?.children
        ?? configuredTreeChildren
    )
    lifecycleEvents.append("begin")
    return candidate
  }

  func append(
    _ batch: FileSystemScanBatch,
    to candidate: ScanID
  ) async throws {
    guard var snapshot = candidates[candidate] else {
      throw SnapshotIndexError.candidateNotFound
    }
    snapshot.items.append(contentsOf: batch.items)
    snapshot.issues.append(contentsOf: batch.issues)
    candidates[candidate] = snapshot
  }

  func largestItems(
    in candidate: ScanID,
    limit: Int
  ) async throws -> [StorageItemSummary] {
    guard
      let snapshot =
        candidates[candidate] ?? completedSnapshots[candidate]
    else {
      throw SnapshotIndexError.candidateNotFound
    }

    return largestItems(from: snapshot, limit: limit)
  }

  func treeRoot(in scan: ScanID) async throws -> StorageTreeItem {
    guard
      let snapshot = candidates[scan] ?? completedSnapshots[scan]
    else {
      throw SnapshotIndexError.candidateNotFound
    }
    return snapshot.treeRoot
  }

  func itemDetail(for itemID: UUID, in scan: ScanID) async throws -> StorageItemDetail? {
    if failsNextItemDetail {
      failsNextItemDetail = false
      throw SnapshotIndexError.statementFailed(code: 1)
    }
    guard let snapshot = candidates[scan] ?? completedSnapshots[scan] else {
      throw SnapshotIndexError.candidateNotFound
    }
    let allItems = [snapshot.treeRoot] + snapshot.treeChildren.values.flatMap { $0 }
    guard let item = allItems.first(where: { $0.id == itemID }) else {
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
  ) async throws {
    guard var snapshot = candidates[scan] ?? completedSnapshots[scan] else {
      throw SnapshotIndexError.candidateNotFound
    }
    let allItems = [snapshot.treeRoot] + snapshot.treeChildren.values.flatMap { $0 }
    guard let target = allItems.first(where: { $0.id == itemID }) else {
      throw SnapshotIndexError.candidateNotFound
    }
    let oldPath = target.location.path(percentEncoded: false)
    func renamed(_ item: StorageTreeItem) -> StorageTreeItem {
      let itemPath = item.location.path(percentEncoded: false)
      let rewrittenPath = PathRelocation.rewritten(
        itemPath,
        oldPrefix: oldPath,
        newPrefix: newPath
      )
      guard rewrittenPath != itemPath else { return item }
      let newLocation = URL(filePath: rewrittenPath)
      return item.id == itemID
        ? item.withRenamed(name: newName, location: newLocation)
        : item.withRelocated(to: newLocation)
    }
    snapshot.treeRoot = renamed(snapshot.treeRoot)
    for (parentID, children) in snapshot.treeChildren {
      snapshot.treeChildren[parentID] = children.map(renamed)
    }
    if candidates[scan] != nil {
      candidates[scan] = snapshot
    } else {
      completedSnapshots[scan] = snapshot
    }
  }

  func descendantCount(of itemID: UUID, in scan: ScanID) async throws -> Int? {
    guard let snapshot = candidates[scan] ?? completedSnapshots[scan] else {
      throw SnapshotIndexError.candidateNotFound
    }
    let allItems = [snapshot.treeRoot] + snapshot.treeChildren.values.flatMap { $0 }
    guard let target = allItems.first(where: { $0.id == itemID }), target.kind == .folder else {
      return nil
    }
    func descendantIDs(of parentID: UUID) -> [UUID] {
      let children = snapshot.treeChildren[parentID] ?? []
      return children.map(\.id) + children.flatMap { descendantIDs(of: $0.id) }
    }
    return descendantIDs(of: itemID).count
  }

  func issues(in scan: ScanID, limit: Int) async throws -> [ScanIssue] {
    guard let snapshot = candidates[scan] ?? completedSnapshots[scan] else {
      throw SnapshotIndexError.candidateNotFound
    }
    return Array(snapshot.issues.prefix(limit))
  }

  func removeItem(_ itemID: UUID, in scan: ScanID) async throws {
    guard var snapshot = candidates[scan] ?? completedSnapshots[scan] else {
      throw SnapshotIndexError.candidateNotFound
    }
    func descendantIDs(of parentID: UUID) -> Set<UUID> {
      let children = snapshot.treeChildren[parentID] ?? []
      return children.reduce(into: Set(children.map(\.id))) { result, child in
        result.formUnion(descendantIDs(of: child.id))
      }
    }
    let removedIDs = descendantIDs(of: itemID).union([itemID])
    snapshot.treeChildren = snapshot.treeChildren.reduce(into: [:]) { result, entry in
      let (parentID, children) = entry
      guard !removedIDs.contains(parentID) else { return }
      result[parentID] = children.filter { !removedIDs.contains($0.id) }
    }
    if candidates[scan] != nil {
      candidates[scan] = snapshot
    } else {
      completedSnapshots[scan] = snapshot
    }
  }

  func directChildren(
    of parentID: UUID,
    in scan: ScanID,
    offset: Int,
    limit: Int
  ) async throws -> StorageTreePage {
    let failuresRemaining = treeFailuresRemaining[parentID] ?? 0
    guard failuresRemaining == 0 else {
      if failuresRemaining != .max {
        treeFailuresRemaining[parentID] = failuresRemaining - 1
      }
      throw SnapshotIndexError.candidateNotFound
    }
    guard
      let snapshot = candidates[scan] ?? completedSnapshots[scan]
    else {
      throw SnapshotIndexError.candidateNotFound
    }
    return page(
      of: parentID,
      in: snapshot,
      offset: offset,
      limit: limit
    )
  }

  func flatItems(
    in scan: ScanID,
    query: AllItemsQuery,
    offset: Int,
    limit: Int
  ) async throws -> AllItemsPage {
    flatItemsCallCount += 1
    guard
      let snapshot = candidates[scan] ?? completedSnapshots[scan]
    else {
      throw SnapshotIndexError.candidateNotFound
    }
    if blocksNextFlatItems {
      blocksNextFlatItems = false
      isFlatItemsBlocked = true
      await withCheckedContinuation { continuation in
        flatItemsContinuation = continuation
      }
      isFlatItemsBlocked = false
    }
    let matches = query.applying(to: snapshot.treeChildren.values.flatMap { $0 })

    let boundedOffset = min(max(0, offset), matches.count)
    let boundedLimit = max(0, limit)
    let end = min(boundedOffset + boundedLimit, matches.count)
    return AllItemsPage(
      items: Array(matches[boundedOffset..<end]),
      nextOffset: end < matches.count ? end : nil
    )
  }

  @discardableResult
  func promoteCandidate(
    _ candidate: ScanID,
    expectedItemCount: Int,
    expectedIssueCount: Int,
    largestItemLimit: Int = 200,
    treePageLimit: Int = 200
  ) async throws -> PromotedScanSnapshot {
    if blocksNextPromotion {
      blocksNextPromotion = false
      isPromotionBlocked = true
      await withCheckedContinuation { continuation in
        promotionContinuation = continuation
      }
      isPromotionBlocked = false
    }
    try Task.checkCancellation()
    guard let snapshot = candidates[candidate] else {
      throw SnapshotIndexError.candidateNotFound
    }
    guard snapshot.items.count == expectedItemCount else {
      throw SnapshotIndexError.itemCountMismatch(
        expected: expectedItemCount,
        actual: snapshot.items.count
      )
    }
    guard snapshot.issues.count == expectedIssueCount else {
      throw SnapshotIndexError.issueCountMismatch(
        expected: expectedIssueCount,
        actual: snapshot.issues.count
      )
    }

    let completedAt = dateProvider.now()
    let promotedSnapshot = PromotedScanSnapshot(
      scanID: candidate,
      scope: snapshot.scope,
      completion: ScanCompletion(
        accessibleItemCount: snapshot.items.count,
        issueCount: snapshot.issues.count
      ),
      completedAt: completedAt,
      expiresAt: completedAt.addingTimeInterval(86_400),
      largestItems: largestItems(
        from: snapshot,
        limit: largestItemLimit
      ),
      treeRoot: snapshot.treeRoot,
      rootPage: page(
        of: snapshot.treeRoot.id,
        in: snapshot,
        offset: 0,
        limit: treePageLimit
      )
    )
    if failsNextPromotionPresentation {
      failsNextPromotionPresentation = false
      throw SnapshotIndexError.integrityCheckFailed
    }
    try Task.checkCancellation()
    completedSnapshots = [candidate: snapshot]
    completedCacheSnapshot = CachedScanSnapshot(
      scanID: promotedSnapshot.scanID,
      scope: promotedSnapshot.scope,
      completion: promotedSnapshot.completion,
      completedAt: promotedSnapshot.completedAt,
      expiresAt: promotedSnapshot.expiresAt,
      largestItems: promotedSnapshot.largestItems,
      treeRoot: promotedSnapshot.treeRoot,
      rootPage: promotedSnapshot.rootPage
    )
    candidates.removeValue(forKey: candidate)
    lifecycleEvents.append("promote")
    return promotedSnapshot
  }

  func discardCandidate(_ candidate: ScanID) async throws {
    if failsNextCandidateDiscard {
      failsNextCandidateDiscard = false
      lifecycleEvents.append("discard-failed")
      throw SnapshotIndexError.statementFailed(code: 1)
    }
    candidates.removeValue(forKey: candidate)
    lifecycleEvents.append("discard")
  }

  func cacheFileSizeBytes() async throws -> Int64? {
    configuredCacheFileSizeBytes
  }

  func setCacheFileSizeBytes(_ bytes: Int64?) {
    configuredCacheFileSizeBytes = bytes
  }

  private func largestItems(
    from snapshot: Snapshot,
    limit: Int
  ) -> [StorageItemSummary] {
    snapshot.items
      .sorted(by: sortsBefore)
      .prefix(max(0, limit))
      .map {
        StorageItemSummary(
          id: $0.id,
          location: $0.location,
          name: $0.name,
          kind: $0.kind,
          diskUsedBytes: $0.diskUsedBytes
        )
      }
  }

  private func page(
    of parentID: UUID,
    in snapshot: Snapshot,
    offset: Int,
    limit: Int
  ) -> StorageTreePage {
    let children = snapshot.treeChildren[parentID] ?? []
    let boundedOffset = min(max(0, offset), children.count)
    let boundedLimit = max(0, limit)
    let end = min(
      boundedOffset + min(boundedLimit, children.count),
      children.count
    )
    return StorageTreePage(
      parentID: parentID,
      items: Array(children[boundedOffset..<end]),
      nextOffset: end < children.count ? end : nil
    )
  }

  private func sortsBefore(_ lhs: ScannedItem, _ rhs: ScannedItem) -> Bool {
    switch (lhs.diskUsedBytes, rhs.diskUsedBytes) {
    case (.some(let lhsBytes), .some(let rhsBytes)):
      if lhsBytes != rhsBytes {
        return lhsBytes > rhsBytes
      }
    case (.some, .none):
      return true
    case (.none, .some):
      return false
    case (.none, .none):
      break
    }

    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
  }
}
