import Foundation
import Observation

struct ScanCacheNotice: Equatable {
  let message: String

  static let expired = Self(
    message: "Saved scan results have expired. Scan again to refresh them."
  )
  static let cleanupFailed = Self(
    message: "Saved scan data couldn’t be removed. Quit and reopen the app."
  )
  static let refreshFailed = Self(
    message: "Saved scan data couldn’t be checked. Try again."
  )
  static let reconstructed = Self(
    message: "Saved scan data was rebuilt after it couldn’t be read."
  )
}

struct CompletedRename: Equatable {
  let itemID: UUID
  let oldName: String
  let newName: String
  let path: String
}

@MainActor
@Observable
final class ExplorerSession {
  private struct FailedTreePageRequest {
    let parentID: UUID
    let offset: Int
    let existingPage: StorageTreePage?
  }

  private(set) var selectedScope: ScanScope
  private(set) var scopeSelection: ScanScopeSelection
  private(set) var scopeDescription: ScanScopeDescription
  private(set) var completedScopeDescription: ScanScopeDescription?
  private(set) var scopeFailureMessage: String?
  private(set) var completedAt: Date?
  private(set) var expiresAt: Date?
  private(set) var cacheNotice: ScanCacheNotice?
  private(set) var scanState: ScanState = .idle
  private(set) var largestItems: [StorageItemSummary] = []
  private(set) var treeRoot: StorageTreeItem?
  private(set) var treePages: [UUID: StorageTreePage] = [:]
  private(set) var expandedTreeItemIDs: Set<UUID> = []
  private(set) var selectedItemID: UUID?
  private(set) var selectedItemDetail: StorageItemDetail?
  private(set) var selectedItemCapability: ItemCapability?
  private(set) var renamingItemID: UUID?
  private(set) var renameValidationMessage: String?
  private(set) var pendingRenameExtensionConfirmation: RenamePlan?
  private(set) var lastRename: CompletedRename?
  private(set) var pendingTrashConfirmation: TrashConfirmation?
  private(set) var trashValidationMessage: String?
  private(set) var loadingTreeItemIDs: Set<UUID> = []
  private(set) var treeLoadFailureMessage: String?
  private(set) var isQuitConfirmationPresented = false
  private(set) var isFullDiskAccessGuidanceDismissed = false

  private static let largestItemLimit = 200
  private static let treePageSize = 200
  private let scanner: any FileSystemScanning
  private let snapshotIndex: any ScanSnapshotIndexing
  private let scopeAuthorizer: any ScanScopeAuthorizing
  private let customScopeBookmarkStore: (any CustomScopeBookmarking)?
  private let dateProvider: any DateProviding
  private var launchPreparationTask: Task<Void, Never>?
  private var expirationTask: Task<Void, Never>?
  private var scanTask: Task<Void, Never>?
  private var scanControl: ScanExecutionControl?
  private var completedScanID: ScanID?
  private var failedTreePageRequests: [UUID: FailedTreePageRequest] = [:]
  private var selectedItemDetailTask: Task<Void, Never>?
  private var pendingProposedRenameName: String?
  private var renameExpectedEvidence: LiveMutationEvidence?
  private var trashExpectedEvidence: LiveMutationEvidence?
  private let mutationEvidenceProvider: any MutationEvidenceProviding
  private let renameExecutor: any RenameExecuting
  private let trashExecutor: any TrashExecuting

  init(
    homeDirectoryURL: URL,
    scanner: any FileSystemScanning,
    snapshotIndex: any ScanSnapshotIndexing,
    scopeAuthorizer: (any ScanScopeAuthorizing)? = nil,
    customScopeBookmarkStore: (any CustomScopeBookmarking)? = nil,
    dateProvider: any DateProviding = SystemDateProvider(),
    mutationEvidenceProvider: any MutationEvidenceProviding = FoundationMutationEvidenceProvider(),
    renameExecutor: any RenameExecuting = FoundationRenameExecutor(),
    trashExecutor: any TrashExecuting = FoundationTrashExecutor()
  ) {
    let fallbackScope = ScanScope.homeFolder(homeDirectoryURL)
    let resolvedAuthorizer =
      scopeAuthorizer
      ?? HomeOnlyScanScopeAuthorizer(homeScope: fallbackScope)
    let initialDescription = resolvedAuthorizer.describe(.homeFolder)
    scopeSelection = .homeFolder
    scopeDescription = initialDescription
    completedScopeDescription = nil
    scopeFailureMessage = nil
    completedAt = nil
    expiresAt = nil
    cacheNotice = nil
    selectedScope =
      initialDescription.availability.availableScope ?? fallbackScope
    self.scanner = scanner
    self.snapshotIndex = snapshotIndex
    self.scopeAuthorizer = resolvedAuthorizer
    self.customScopeBookmarkStore = customScopeBookmarkStore
    self.dateProvider = dateProvider
    self.mutationEvidenceProvider = mutationEvidenceProvider
    self.renameExecutor = renameExecutor
    self.trashExecutor = trashExecutor
    launchPreparationTask = Task(priority: .utility) { [weak self] in
      await self?.prepareCacheForLaunch()
    }
  }

  func waitForLaunchPreparation() async {
    await launchPreparationTask?.value
  }

  @discardableResult
  func selectHomeFolder() -> Bool {
    selectScope(.homeFolder)
  }

  @discardableResult
  func selectEntireInternalDisk() -> Bool {
    selectScope(.entireInternalDisk)
  }

  @discardableResult
  func selectCustomScope(_ reference: CustomScopeReference) -> Bool {
    selectScope(.custom(reference))
  }

  @discardableResult
  func approveCustomScope(_ location: URL) -> Bool {
    guard scanTask == nil, let customScopeBookmarkStore else {
      return false
    }
    do {
      let reference = try customScopeBookmarkStore.replaceApprovedLocation(
        location
      )
      return selectCustomScope(reference)
    } catch {
      scopeFailureMessage = "The selected location could not be saved."
      return false
    }
  }

  func dismissFullDiskAccessGuidance() {
    isFullDiskAccessGuidanceDismissed = true
  }

  var canChangeScope: Bool {
    scanTask == nil
  }

  @discardableResult
  func startScan() -> Bool {
    guard scanTask == nil else {
      return false
    }

    let preparation = scopeAuthorizer.prepare(scopeSelection)
    guard case .ready(let preparedScope) = preparation else {
      if case .unavailable(let description) = preparation {
        scopeDescription = description
        scopeFailureMessage = Self.scopeFailureMessage(
          for: description.availability
        )
      }
      return false
    }
    let scope = preparedScope.scope
    selectedScope = scope
    let preparedDescription = ScanScopeDescription(
      selection: scopeSelection,
      availability: .available(scope)
    )
    scopeDescription = preparedDescription
    scopeFailureMessage = nil
    let control = ScanExecutionControl()
    scanControl = control
    scanState = .scanning(.initial)
    scanTask = Task(priority: .utility) { [weak self] in
      await self?.runScan(
        for: scope,
        scopeDescription: preparedDescription,
        accessLease: preparedScope.accessLease,
        control: control
      )
    }
    return true
  }

  func pauseScan() async -> Bool {
    guard
      case .scanning(let progress) = scanState,
      let scanControl,
      await scanControl.pause()
    else {
      return false
    }
    scanState = .paused(progress)
    return true
  }

  func resumeScan() async -> Bool {
    guard
      case .paused(let progress) = scanState,
      let scanControl
    else {
      return false
    }
    scanState = .resuming(progress)
    guard await scanControl.resume() else {
      scanState = .paused(progress)
      return false
    }
    return true
  }

  func cancelScan() async -> Bool {
    guard
      let progress = activeScanProgress,
      let scanTask,
      let scanControl
    else {
      return false
    }
    scanState = .cancelling(progress)
    scanTask.cancel()
    await scanControl.cancel()
    await scanTask.value
    return scanState == .cancelled
  }

  func replaceScan() async -> Bool {
    if activeScanProgress != nil {
      guard await cancelScan() else {
        return false
      }
    }
    return startScan()
  }

  func requestQuit() -> QuitDisposition {
    guard hasActiveScan else {
      isQuitConfirmationPresented = false
      return .terminateNow
    }
    isQuitConfirmationPresented = true
    return .confirmScanCancellation
  }

  func dismissQuitConfirmation() {
    isQuitConfirmationPresented = false
  }

  func confirmQuit() async -> Bool {
    guard isQuitConfirmationPresented else {
      return false
    }
    isQuitConfirmationPresented = false

    if activeScanProgress != nil {
      return await cancelScan()
    }
    if case .cancelling = scanState, let scanTask {
      await scanTask.value
      return scanState == .cancelled
    }
    return true
  }

  func selectItem(_ itemID: UUID?) {
    selectedItemID = itemID
    guard let itemID, let completedScanID else {
      selectedItemDetail = nil
      selectedItemCapability = nil
      selectedItemDetailTask?.cancel()
      return
    }
    let requestedScanID = completedScanID
    selectedItemDetailTask?.cancel()
    selectedItemDetailTask = Task { [weak self] in
      await self?.loadSelectedItemDetail(for: itemID, in: requestedScanID)
    }
  }

  func waitForSelectedItemDetail() async {
    await selectedItemDetailTask?.value
  }

  private func loadSelectedItemDetail(for itemID: UUID, in scanID: ScanID) async {
    do {
      let detail = try await snapshotIndex.itemDetail(for: itemID, in: scanID)
      guard self.selectedItemID == itemID, self.completedScanID == scanID else {
        return
      }
      selectedItemDetail = detail
      selectedItemCapability = detail.map {
        capability(for: $0.item, volume: $0.volumeCharacteristics)
      }
    } catch {
      guard self.selectedItemID == itemID, self.completedScanID == scanID else {
        return
      }
      selectedItemDetail = nil
      selectedItemCapability = nil
    }
  }

  func beginRename(_ itemID: UUID) async {
    if selectedItemID != itemID {
      selectItem(itemID)
    }
    await waitForSelectedItemDetail()
    guard
      selectedItemCapability?.canRename == true,
      let detail = selectedItemDetail,
      detail.item.id == itemID
    else {
      return
    }
    let path = detail.item.location.path(percentEncoded: false)
    guard let evidence = mutationEvidenceProvider.liveEvidence(at: path) else {
      renameValidationMessage = "This item can no longer be found."
      return
    }
    renamingItemID = itemID
    renameValidationMessage = nil
    pendingProposedRenameName = nil
    renameExpectedEvidence = evidence
  }

  func updateRenameProposal(_ proposedName: String) {
    guard
      let renamingItemID,
      let currentName = currentItemName(for: renamingItemID)
    else {
      return
    }
    pendingProposedRenameName = proposedName
    let siblingNames = siblingNames(excluding: renamingItemID)
    if let error = RenameValidation.validate(
      currentName: currentName,
      proposedName: proposedName,
      siblingNames: siblingNames
    ) {
      renameValidationMessage = Self.message(for: error)
    } else {
      renameValidationMessage = nil
    }
  }

  func cancelRename() {
    renamingItemID = nil
    renameValidationMessage = nil
    pendingRenameExtensionConfirmation = nil
    pendingProposedRenameName = nil
    renameExpectedEvidence = nil
  }

  @discardableResult
  func commitRename() async -> Bool {
    guard
      let renamingItemID,
      renameValidationMessage == nil,
      let detail = selectedItemDetail,
      detail.item.id == renamingItemID,
      let capability = selectedItemCapability,
      capability.canRename,
      let completedScanID,
      let expectedEvidence = renameExpectedEvidence
    else {
      return false
    }
    let proposedName = pendingProposedRenameName ?? detail.item.name
    if RenameValidation.requiresExtensionChangeConfirmation(
      currentName: detail.item.name,
      proposedName: proposedName
    ), pendingRenameExtensionConfirmation == nil {
      pendingRenameExtensionConfirmation = RenamePlan(
        currentPath: detail.item.location.path(percentEncoded: false),
        parentPath: detail.item.location.deletingLastPathComponent()
          .path(percentEncoded: false),
        proposedName: proposedName,
        requiresExtensionChangeConfirmation: true
      )
      return false
    }
    return await performRename(
      itemID: renamingItemID,
      currentDetail: detail,
      proposedName: proposedName,
      scanID: completedScanID,
      expectedEvidence: expectedEvidence
    )
  }

  @discardableResult
  func confirmRenameExtensionChange() async -> Bool {
    guard
      pendingRenameExtensionConfirmation != nil,
      let renamingItemID,
      let detail = selectedItemDetail,
      detail.item.id == renamingItemID,
      let completedScanID,
      let expectedEvidence = renameExpectedEvidence
    else {
      return false
    }
    let plan = pendingRenameExtensionConfirmation
    pendingRenameExtensionConfirmation = nil
    guard let plan else {
      return false
    }
    return await performRename(
      itemID: renamingItemID,
      currentDetail: detail,
      proposedName: plan.proposedName,
      scanID: completedScanID,
      expectedEvidence: expectedEvidence
    )
  }

  func dismissRenameExtensionConfirmation() {
    pendingRenameExtensionConfirmation = nil
  }

  @discardableResult
  func undoLastRename() async -> Bool {
    guard let lastRename, let completedScanID else {
      self.lastRename = nil
      return false
    }
    guard
      let detail = try? await snapshotIndex.itemDetail(
        for: lastRename.itemID,
        in: completedScanID
      )
    else {
      self.lastRename = nil
      return false
    }
    // Undo is a single immediate action, not a multi-second edit window, so
    // capturing live evidence right before validating here (rather than at
    // some earlier "begin" moment) is correct — there is no earlier moment.
    guard
      let expectedEvidence = mutationEvidenceProvider.liveEvidence(
        at: detail.item.location.path(percentEncoded: false)
      )
    else {
      self.lastRename = nil
      return false
    }
    let succeeded = await performRename(
      itemID: lastRename.itemID,
      currentDetail: detail,
      proposedName: lastRename.oldName,
      scanID: completedScanID,
      expectedEvidence: expectedEvidence
    )
    self.lastRename = nil
    return succeeded
  }

  private func performRename(
    itemID: UUID,
    currentDetail: StorageItemDetail,
    proposedName: String,
    scanID: ScanID,
    expectedEvidence: LiveMutationEvidence
  ) async -> Bool {
    let path = currentDetail.item.location.path(percentEncoded: false)
    if let error = RenameValidation.validate(
      currentName: currentDetail.item.name,
      proposedName: proposedName,
      siblingNames: siblingNames(excluding: itemID)
    ) {
      renameValidationMessage = Self.message(for: error)
      return false
    }
    let target = ExpectedMutationTarget(
      scanID: scanID,
      volumeIdentity: selectedScope.volumeIdentity,
      path: path,
      kind: currentDetail.item.kind,
      expectedEvidence: expectedEvidence
    )
    let outcome = RenameOperation.perform(
      expected: target,
      proposedName: proposedName,
      liveEvidenceProvider: mutationEvidenceProvider,
      executor: renameExecutor
    )
    switch outcome {
    case .renamed(let newPath):
      do {
        try await snapshotIndex.updateItemName(
          itemID,
          in: scanID,
          newName: proposedName,
          newPath: newPath
        )
      } catch {
        renameValidationMessage = "This item was renamed but couldn’t be saved."
        renamingItemID = nil
        pendingRenameExtensionConfirmation = nil
        pendingProposedRenameName = nil
        renameExpectedEvidence = nil
        return false
      }
      applyRenamedItem(itemID: itemID, oldPath: path, newName: proposedName, newPath: newPath)
      lastRename = CompletedRename(
        itemID: itemID,
        oldName: currentDetail.item.name,
        newName: proposedName,
        path: newPath
      )
      renamingItemID = nil
      pendingRenameExtensionConfirmation = nil
      pendingProposedRenameName = nil
      renameExpectedEvidence = nil
      renameValidationMessage = nil
      return true
    case .rejected(let reason):
      renameValidationMessage = reason
      return false
    }
  }

  func beginTrashConfirmation(_ itemID: UUID) async {
    if selectedItemID != itemID {
      selectItem(itemID)
    }
    await waitForSelectedItemDetail()
    guard
      selectedItemCapability?.canTrash == true,
      let detail = selectedItemDetail,
      detail.item.id == itemID,
      let completedScanID
    else {
      return
    }
    let path = detail.item.location.path(percentEncoded: false)
    guard let evidence = mutationEvidenceProvider.liveEvidence(at: path) else {
      trashValidationMessage = "This item can no longer be found."
      return
    }
    let descendantCount = try? await snapshotIndex.descendantCount(
      of: itemID,
      in: completedScanID
    )
    trashExpectedEvidence = evidence
    trashValidationMessage = nil
    pendingTrashConfirmation = TrashConfirmation(
      itemID: itemID,
      name: detail.item.name,
      path: path,
      diskUsedBytes: detail.item.diskUsedBytes,
      descendantCount: descendantCount ?? nil,
      warnsAboutCloudSync: detail.item.isCloudOnly
    )
  }

  @discardableResult
  func confirmTrash() async -> Bool {
    guard
      let pendingTrashConfirmation,
      let detail = selectedItemDetail,
      detail.item.id == pendingTrashConfirmation.itemID,
      let capability = selectedItemCapability,
      capability.canTrash,
      let completedScanID,
      let expectedEvidence = trashExpectedEvidence
    else {
      return false
    }
    let itemID = pendingTrashConfirmation.itemID
    let path = detail.item.location.path(percentEncoded: false)
    let target = ExpectedMutationTarget(
      scanID: completedScanID,
      volumeIdentity: selectedScope.volumeIdentity,
      path: path,
      kind: detail.item.kind,
      expectedEvidence: expectedEvidence
    )
    let outcome = TrashOperation.perform(
      expected: target,
      liveEvidenceProvider: mutationEvidenceProvider,
      executor: trashExecutor
    )
    switch outcome {
    case .trashed:
      do {
        try await snapshotIndex.removeItem(itemID, in: completedScanID)
      } catch {
        trashValidationMessage = "This item was moved to Trash but couldn’t be saved."
        self.pendingTrashConfirmation = nil
        trashExpectedEvidence = nil
        return false
      }
      applyTrashedItem(itemID)
      self.pendingTrashConfirmation = nil
      trashExpectedEvidence = nil
      trashValidationMessage = nil
      return true
    case .rejected(let reason):
      trashValidationMessage = reason
      return false
    }
  }

  func dismissTrashConfirmation() {
    pendingTrashConfirmation = nil
    trashExpectedEvidence = nil
    trashValidationMessage = nil
  }

  private func applyTrashedItem(_ itemID: UUID) {
    func descendantIDs(of parentID: UUID) -> Set<UUID> {
      let children = treePages[parentID]?.items ?? []
      return children.reduce(into: Set(children.map(\.id))) { result, child in
        result.formUnion(descendantIDs(of: child.id))
      }
    }
    let removedIDs = descendantIDs(of: itemID).union([itemID])
    for (parentID, page) in treePages {
      guard !removedIDs.contains(parentID) else {
        treePages.removeValue(forKey: parentID)
        continue
      }
      treePages[parentID] = StorageTreePage(
        parentID: page.parentID,
        items: page.items.filter { !removedIDs.contains($0.id) },
        nextOffset: page.nextOffset
      )
    }
    expandedTreeItemIDs.subtract(removedIDs)
    if let selectedItemID, removedIDs.contains(selectedItemID) {
      selectItem(nil)
    }
    if selectedItemDetail.map({ removedIDs.contains($0.item.id) }) == true {
      selectedItemDetail = nil
      selectedItemCapability = nil
    }
  }

  private func applyRenamedItem(itemID: UUID, oldPath: String, newName: String, newPath: String) {
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
    if let treeRoot {
      self.treeRoot = renamed(treeRoot)
    }
    for (parentID, page) in treePages {
      treePages[parentID] = StorageTreePage(
        parentID: page.parentID,
        items: page.items.map(renamed),
        nextOffset: page.nextOffset
      )
    }
    if selectedItemDetail?.item.id == itemID {
      selectedItemDetail = StorageItemDetail(
        item: renamed(selectedItemDetail!.item),
        volumeCharacteristics: selectedItemDetail!.volumeCharacteristics
      )
    }
  }

  func capability(for item: StorageTreeItem) -> ItemCapability {
    capability(for: item, volume: selectedScope.volumeCharacteristics)
  }

  private func capability(
    for item: StorageTreeItem,
    volume: ScanVolumeCharacteristics
  ) -> ItemCapability {
    RestrictionPolicy.capability(
      for: RestrictionPolicy.classify(
        path: item.location.path(percentEncoded: false),
        kind: item.kind,
        isRoot: item.isRoot,
        isPackageDescendant: false,
        isShared: item.isShared,
        volume: volume
      )
    )
  }

  private func currentItemName(for itemID: UUID) -> String? {
    if treeRoot?.id == itemID {
      return treeRoot?.name
    }
    for page in treePages.values {
      if let item = page.items.first(where: { $0.id == itemID }) {
        return item.name
      }
    }
    return nil
  }

  private func siblingNames(excluding itemID: UUID) -> Set<String> {
    for page in treePages.values {
      guard page.items.contains(where: { $0.id == itemID }) else {
        continue
      }
      return Set(page.items.filter { $0.id != itemID }.map(\.name))
    }
    return []
  }

  private static func message(for error: RenameValidationError) -> String {
    switch error {
    case .empty:
      "Name can’t be empty."
    case .containsPathSeparator:
      "Name can’t contain “/” or “:”."
    case .isDotOrDotDot:
      "Name can’t be “.” or “..”."
    case .invalidPlatformName:
      "Name contains a character that isn’t allowed."
    case .collidesWithExistingName:
      "An item with that name already exists here."
    }
  }

  func setTreeItem(_ itemID: UUID, expanded: Bool) {
    guard expanded else {
      expandedTreeItemIDs.remove(itemID)
      return
    }

    expandedTreeItemIDs.insert(itemID)
    guard treePages[itemID] == nil else {
      return
    }
    Task { [weak self] in
      await self?.loadTreePage(
        for: itemID,
        offset: 0,
        existingPage: nil
      )
    }
  }

  func loadNextTreePage(for parentID: UUID) async {
    guard
      let currentPage = treePages[parentID],
      let nextOffset = currentPage.nextOffset
    else {
      return
    }

    await loadTreePage(
      for: parentID,
      offset: nextOffset,
      existingPage: currentPage
    )
  }

  func retryFailedTreePages() async {
    let requests = Array(failedTreePageRequests.values)
    for request in requests {
      await loadTreePage(
        for: request.parentID,
        offset: request.offset,
        existingPage: request.existingPage
      )
    }
  }

  func refreshCacheLifecycle() async {
    do {
      let preparation = try await snapshotIndex.refreshCompletedCache(
        largestItemLimit: Self.largestItemLimit,
        treePageLimit: Self.treePageSize
      )
      applyCachePreparation(preparation, updatesSelectedScope: false)
    } catch {
      guard shouldFailClosedAfterCacheRefreshError else {
        cacheNotice = .refreshFailed
        return
      }
      expirationTask?.cancel()
      expirationTask = nil
      clearCompletedPresentation()
      cacheNotice = .cleanupFailed
      if !hasActiveScan {
        scanState = .idle
      }
    }
  }

  func clearScanData() async -> Bool {
    do {
      try await snapshotIndex.clearCompletedSnapshot()
      expirationTask?.cancel()
      expirationTask = nil
      clearCompletedPresentation()
      if !hasActiveScan {
        scanState = .idle
      }
      cacheNotice = nil
      return true
    } catch {
      cacheNotice = .cleanupFailed
      return false
    }
  }

  private func loadTreePage(
    for parentID: UUID,
    offset: Int,
    existingPage: StorageTreePage?
  ) async {
    guard
      let completedScanID,
      !loadingTreeItemIDs.contains(parentID)
    else {
      return
    }

    loadingTreeItemIDs.insert(parentID)
    defer {
      loadingTreeItemIDs.remove(parentID)
    }

    do {
      let nextPage = try await snapshotIndex.directChildren(
        of: parentID,
        in: completedScanID,
        offset: offset,
        limit: Self.treePageSize
      )
      guard self.completedScanID == completedScanID else {
        return
      }
      let currentItems = existingPage?.items ?? []
      let existingIDs = Set(currentItems.map(\.id))
      let newItems = nextPage.items.filter {
        !existingIDs.contains($0.id)
      }
      treePages[parentID] = StorageTreePage(
        parentID: parentID,
        items: currentItems + newItems,
        nextOffset: nextPage.nextOffset
      )
      if failedTreePageRequests[parentID]?.offset == offset {
        failedTreePageRequests.removeValue(forKey: parentID)
        if failedTreePageRequests.isEmpty {
          treeLoadFailureMessage = nil
        }
      }
    } catch {
      failedTreePageRequests[parentID] = FailedTreePageRequest(
        parentID: parentID,
        offset: offset,
        existingPage: existingPage
      )
      treeLoadFailureMessage = "Some items couldn’t be loaded."
    }
  }

  private var activeScanProgress: ScanProgress? {
    switch scanState {
    case .scanning(let progress),
      .paused(let progress),
      .resuming(let progress):
      progress
    case .idle, .cancelling, .cancelled, .completed, .failed:
      nil
    }
  }

  private var hasActiveScan: Bool {
    switch scanState {
    case .scanning, .paused, .resuming, .cancelling:
      true
    case .idle, .cancelled, .completed, .failed:
      false
    }
  }

  private var shouldFailClosedAfterCacheRefreshError: Bool {
    guard let completedAt, let expiresAt else {
      return false
    }
    let now = dateProvider.now()
    let completedInterval = completedAt.timeIntervalSince1970
    let expiryInterval = expiresAt.timeIntervalSince1970
    let nowInterval = now.timeIntervalSince1970
    return !completedInterval.isFinite
      || !expiryInterval.isFinite
      || !nowInterval.isFinite
      || expiryInterval != completedInterval + 86_400
      || now < completedAt
      || now >= expiresAt
  }

  private func runScan(
    for scope: ScanScope,
    scopeDescription: ScanScopeDescription,
    accessLease: any ScanScopeAccessLeasing,
    control: ScanExecutionControl
  ) async {
    var candidate: ScanID?
    do {
      await waitForLaunchPreparation()
      let newCandidate = try await snapshotIndex.beginCandidate(for: scope)
      candidate = newCandidate
      let batches = await scanner.batches(for: scope)
      var latestProgress = ScanProgress.initial
      var iterator = batches.makeAsyncIterator()
      while true {
        try await control.waitUntilRunning()
        publishResumedStateIfNeeded(progress: latestProgress)
        guard let batch = try await iterator.next() else {
          try await control.waitUntilRunning()
          publishResumedStateIfNeeded(progress: latestProgress)
          break
        }
        try Task.checkCancellation()
        try await snapshotIndex.append(batch, to: newCandidate)
        if completedScanID == nil {
          largestItems = try await snapshotIndex.largestItems(
            in: newCandidate,
            limit: Self.largestItemLimit
          )
        }
        latestProgress = batch.progress
        publishScanProgress(batch.progress)
      }
      try Task.checkCancellation()
      let promotedSnapshot = try await snapshotIndex.promoteCandidate(
        newCandidate,
        expectedItemCount: latestProgress.discoveredItemCount,
        expectedIssueCount: latestProgress.issueCount,
        largestItemLimit: Self.largestItemLimit,
        treePageLimit: Self.treePageSize
      )
      largestItems = promotedSnapshot.largestItems
      treeRoot = promotedSnapshot.treeRoot
      treePages = [
        promotedSnapshot.treeRoot.id: promotedSnapshot.rootPage
      ]
      expandedTreeItemIDs = [promotedSnapshot.treeRoot.id]
      selectedItemID = nil
      loadingTreeItemIDs = []
      completedScanID = newCandidate
      completedScopeDescription = scopeDescription
      completedAt = promotedSnapshot.completedAt
      expiresAt = promotedSnapshot.expiresAt
      cacheNotice = nil
      failedTreePageRequests = [:]
      treeLoadFailureMessage = nil
      scanState = .completed(
        ScanCompletion(
          accessibleItemCount: latestProgress.discoveredItemCount,
          issueCount: latestProgress.issueCount
        )
      )
      scheduleExpiration(for: promotedSnapshot.expiresAt)
    } catch is CancellationError {
      if let candidate {
        do {
          try await discardCandidateOrCleanup(candidate)
          scanState = .cancelled
        } catch {
          scanState = .failed(
            ScanFailure(
              message:
                "The incomplete scan couldn’t be removed. Quit and reopen the app."
            )
          )
        }
      } else {
        scanState = .cancelled
      }
      clearPresentationIfNoCompletedScan()
    } catch {
      var cleanupSucceeded = true
      if let candidate {
        do {
          try await discardCandidateOrCleanup(candidate)
        } catch {
          cleanupSucceeded = false
        }
      }
      clearPresentationIfNoCompletedScan()
      scanState = .failed(
        ScanFailure(
          message:
            cleanupSucceeded
            ? "The scan couldn’t be completed."
            : "The incomplete scan couldn’t be removed. Quit and reopen the app."
        )
      )
    }
    accessLease.finish()
    scanTask = nil
    scanControl = nil
  }

  private func publishResumedStateIfNeeded(
    progress: ScanProgress
  ) {
    if case .resuming = scanState {
      scanState = .scanning(progress)
    }
  }

  private func publishScanProgress(_ progress: ScanProgress) {
    switch scanState {
    case .paused:
      scanState = .paused(progress)
    case .resuming:
      scanState = .resuming(progress)
    case .cancelling:
      scanState = .cancelling(progress)
    case .idle, .scanning, .cancelled, .completed, .failed:
      scanState = .scanning(progress)
    }
  }

  private func clearPresentationIfNoCompletedScan() {
    guard completedScanID == nil else {
      return
    }
    largestItems = []
    treeRoot = nil
    treePages = [:]
    expandedTreeItemIDs = []
    selectedItemID = nil
    loadingTreeItemIDs = []
    failedTreePageRequests = [:]
    treeLoadFailureMessage = nil
    completedScopeDescription = nil
    completedAt = nil
    expiresAt = nil
  }

  private func prepareCacheForLaunch() async {
    do {
      let preparation = try await snapshotIndex.prepareCacheForLaunch(
        largestItemLimit: Self.largestItemLimit,
        treePageLimit: Self.treePageSize
      )
      applyCachePreparation(
        preparation,
        updatesSelectedScope: scanTask == nil
      )
    } catch {
      cacheNotice = .cleanupFailed
    }
  }

  private func applyCachePreparation(
    _ preparation: ScanCachePreparation,
    updatesSelectedScope: Bool
  ) {
    switch preparation {
    case .empty:
      break
    case .available(let snapshot):
      if completedScanID == snapshot.scanID {
        if cacheNotice == .refreshFailed {
          cacheNotice = nil
        }
        scheduleExpiration(for: snapshot.expiresAt)
        return
      }
      applyCachedSnapshot(snapshot, updatesSelectedScope: updatesSelectedScope)
    case .expired(let previousScope, _):
      expirationTask?.cancel()
      expirationTask = nil
      clearCompletedPresentation()
      applyPreviousScope(previousScope, updatesSelectedScope: updatesSelectedScope)
      cacheNotice = .expired
      if !hasActiveScan {
        scanState = .idle
      }
    case .cleanupFailed(let previousScope, _):
      expirationTask?.cancel()
      expirationTask = nil
      clearCompletedPresentation()
      if let previousScope {
        applyPreviousScope(
          previousScope,
          updatesSelectedScope: updatesSelectedScope
        )
      }
      cacheNotice = .cleanupFailed
      if !hasActiveScan {
        scanState = .idle
      }
    case .reconstructed:
      expirationTask?.cancel()
      expirationTask = nil
      clearCompletedPresentation()
      cacheNotice = .reconstructed
      if !hasActiveScan {
        scanState = .idle
      }
    }
  }

  private func applyCachedSnapshot(
    _ snapshot: CachedScanSnapshot,
    updatesSelectedScope: Bool
  ) {
    let description = ScanScopeDescription(
      selection: Self.selection(for: snapshot.scope),
      availability: .available(snapshot.scope)
    )
    completedScanID = snapshot.scanID
    completedScopeDescription = description
    completedAt = snapshot.completedAt
    expiresAt = snapshot.expiresAt
    largestItems = snapshot.largestItems
    treeRoot = snapshot.treeRoot
    treePages = [snapshot.treeRoot.id: snapshot.rootPage]
    expandedTreeItemIDs = [snapshot.treeRoot.id]
    selectedItemID = nil
    loadingTreeItemIDs = []
    failedTreePageRequests = [:]
    treeLoadFailureMessage = nil
    cacheNotice = nil
    if updatesSelectedScope {
      selectedScope = snapshot.scope
      scopeSelection = description.selection
      scopeDescription = description
      scopeFailureMessage = nil
      scanState = .completed(snapshot.completion)
    }
    scheduleExpiration(for: snapshot.expiresAt)
  }

  private func clearCompletedPresentation() {
    completedScanID = nil
    clearPresentationIfNoCompletedScan()
  }

  private func applyPreviousScope(
    _ scope: ScanScope,
    updatesSelectedScope: Bool
  ) {
    guard updatesSelectedScope else {
      return
    }
    let description = ScanScopeDescription(
      selection: Self.selection(for: scope),
      availability: .available(scope)
    )
    selectedScope = scope
    scopeSelection = description.selection
    scopeDescription = description
    scopeFailureMessage = nil
  }

  private func scheduleExpiration(for expiry: Date) {
    expirationTask?.cancel()
    let delay = expiry.timeIntervalSince(dateProvider.now())
    guard delay > 0 else {
      expirationTask = Task { [weak self] in
        await self?.refreshCacheLifecycle()
      }
      return
    }
    expirationTask = Task { [weak self] in
      let nanoseconds = UInt64(delay * 1_000_000_000)
      try? await Task.sleep(nanoseconds: nanoseconds)
      guard !Task.isCancelled else {
        return
      }
      await self?.refreshCacheLifecycle()
    }
  }

  private func discardCandidateOrCleanup(_ candidate: ScanID) async throws {
    do {
      try await snapshotIndex.discardCandidate(candidate)
    } catch {
      try await snapshotIndex.removeCrashLeftoverCandidates()
    }
  }

  private func selectScope(_ selection: ScanScopeSelection) -> Bool {
    guard scanTask == nil else {
      return false
    }
    let description = scopeAuthorizer.describe(selection)
    scopeSelection = selection
    scopeDescription = description
    scopeFailureMessage = nil
    if let scope = description.availability.availableScope {
      selectedScope = scope
    }
    return true
  }

  private static func scopeFailureMessage(
    for availability: ScanScopeAvailability
  ) -> String? {
    switch availability {
    case .available:
      nil
    case .disconnected:
      "The selected location is no longer available."
    case .unsupported:
      "The selected volume isn’t supported."
    }
  }

  private static func selection(for scope: ScanScope) -> ScanScopeSelection {
    switch scope.kind {
    case .homeFolder:
      .homeFolder
    case .entireInternalDisk:
      .entireInternalDisk
    case .custom:
      .custom(
        CustomScopeReference(
          displayName: scope.location.lastPathComponent,
          lastKnownLocation: scope.location
        )
      )
    }
  }
}

private struct HomeOnlyScanScopeAuthorizer: ScanScopeAuthorizing {
  let homeScope: ScanScope

  func describe(_ selection: ScanScopeSelection) -> ScanScopeDescription {
    let availability: ScanScopeAvailability
    switch selection {
    case .homeFolder:
      availability = .available(homeScope)
    case .entireInternalDisk:
      availability = .unsupported(location: URL(filePath: "/"))
    case .custom(let reference):
      availability = .disconnected(
        lastKnownLocation: reference.lastKnownLocation
      )
    }
    return ScanScopeDescription(
      selection: selection,
      availability: availability
    )
  }

  func prepare(_ selection: ScanScopeSelection) -> ScanScopePreparation {
    let description = describe(selection)
    guard case .available(let scope) = description.availability else {
      return .unavailable(description)
    }
    return .ready(
      PreparedScanScope(
        scope: scope,
        accessLease: HomeScopeAccessLease()
      )
    )
  }
}

private struct HomeScopeAccessLease: ScanScopeAccessLeasing {
  func finish() {}
}
