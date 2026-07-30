import Foundation
import Observation

@MainActor
@Observable
final class ExplorerSession {
  private struct FailedTreePageRequest {
    let parentID: UUID
    let offset: Int
    let existingPage: StorageTreePage?
  }

  private(set) var selectedScope: ScanScope
  private(set) var scanState: ScanState = .idle
  private(set) var largestItems: [StorageItemSummary] = []
  private(set) var treeRoot: StorageTreeItem?
  private(set) var treePages: [UUID: StorageTreePage] = [:]
  private(set) var expandedTreeItemIDs: Set<UUID> = []
  private(set) var selectedTreeItemID: UUID?
  private(set) var loadingTreeItemIDs: Set<UUID> = []
  private(set) var treeLoadFailureMessage: String?
  private(set) var isQuitConfirmationPresented = false

  private static let largestItemLimit = 200
  private static let treePageSize = 200
  private let scanner: any FileSystemScanning
  private let snapshotIndex: any ScanSnapshotIndexing
  private let launchPreparationTask: Task<Void, any Error>
  private var scanTask: Task<Void, Never>?
  private var scanControl: ScanExecutionControl?
  private var completedScanID: ScanID?
  private var failedTreePageRequests: [UUID: FailedTreePageRequest] = [:]

  init(
    homeDirectoryURL: URL,
    scanner: any FileSystemScanning,
    snapshotIndex: any ScanSnapshotIndexing
  ) {
    selectedScope = .homeFolder(homeDirectoryURL)
    self.scanner = scanner
    self.snapshotIndex = snapshotIndex
    launchPreparationTask = Task(priority: .utility) {
      try await snapshotIndex.removeCrashLeftoverCandidates()
    }
  }

  @discardableResult
  func startScan() -> Bool {
    guard scanTask == nil else {
      return false
    }

    let scope = selectedScope
    let control = ScanExecutionControl()
    scanControl = control
    scanState = .scanning(.initial)
    scanTask = Task(priority: .utility) { [weak self] in
      await self?.runScan(for: scope, control: control)
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
    await scanControl.cancel()
    scanTask.cancel()
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

  func selectTreeItem(_ itemID: UUID?) {
    selectedTreeItemID = itemID
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

  private func runScan(
    for scope: ScanScope,
    control: ScanExecutionControl
  ) async {
    var candidate: ScanID?
    do {
      try await launchPreparationTask.value
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
      try await snapshotIndex.promoteCandidate(
        newCandidate,
        expectedItemCount: latestProgress.discoveredItemCount,
        expectedIssueCount: latestProgress.issueCount
      )
      largestItems = try await snapshotIndex.largestItems(
        in: newCandidate,
        limit: Self.largestItemLimit
      )
      let root = try await snapshotIndex.treeRoot(in: newCandidate)
      let rootPage = try await snapshotIndex.directChildren(
        of: root.id,
        in: newCandidate,
        offset: 0,
        limit: Self.treePageSize
      )
      treeRoot = root
      treePages = [root.id: rootPage]
      expandedTreeItemIDs = [root.id]
      selectedTreeItemID = nil
      loadingTreeItemIDs = []
      completedScanID = newCandidate
      failedTreePageRequests = [:]
      treeLoadFailureMessage = nil
      scanState = .completed(
        ScanCompletion(
          accessibleItemCount: latestProgress.discoveredItemCount,
          issueCount: latestProgress.issueCount
        )
      )
    } catch is CancellationError {
      if let candidate {
        do {
          try await snapshotIndex.discardCandidate(candidate)
          scanState = .cancelled
        } catch {
          scanState = .failed(
            ScanFailure(message: "The scan couldn’t be completed.")
          )
        }
      } else {
        scanState = .cancelled
      }
      clearPresentationIfNoCompletedScan()
    } catch {
      if let candidate {
        try? await snapshotIndex.discardCandidate(candidate)
      }
      clearPresentationIfNoCompletedScan()
      scanState = .failed(
        ScanFailure(message: "The scan couldn’t be completed.")
      )
    }
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
    selectedTreeItemID = nil
    loadingTreeItemIDs = []
    failedTreePageRequests = [:]
    treeLoadFailureMessage = nil
  }
}
