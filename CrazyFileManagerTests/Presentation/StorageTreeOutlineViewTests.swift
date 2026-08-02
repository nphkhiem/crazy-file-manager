import AppKit
import Foundation
import Testing

@testable import CrazyFileManager

@MainActor
@Suite("Storage Tree Outline View")
struct StorageTreeOutlineViewTests {
  @Test
  func givenCompletedScanWithTreeRoot_whenResultsContentIsResolved_thenTreeIsDefault() {
    let fixture = StorageTreeOutlineFixture()

    let contentMode = ResultsView.contentMode(
      for: .completed(
        ScanCompletion(
          accessibleItemCount: 2,
          issueCount: 0
        )
      ),
      treeRoot: fixture.root
    )

    #expect(contentMode == .tree)
  }

  @Test
  func givenReplacementScanWithCompletedTree_whenResultsContentIsResolved_thenTreeRemainsVisible() {
    let fixture = StorageTreeOutlineFixture()

    let contentMode = ResultsView.contentMode(
      for: .scanning(.initial),
      treeRoot: fixture.root
    )

    #expect(contentMode == .tree)
  }

  @Test
  func givenFocusedSelectedExpandedOutline_whenAdjacentRowsArrive_thenInteractionStateIsRestored() {
    let fixture = StorageTreeOutlineFixture()
    let controller = StorageTreeOutlineController()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = controller
    controller.apply(fixture.initialSnapshot)
    #expect(window.makeFirstResponder(controller.outlineView))

    controller.apply(fixture.snapshotWithAdjacentChild)

    #expect(controller.expandedItemIDs == [fixture.root.id])
    #expect(controller.selectedItemID == fixture.firstChild.id)
    #expect(window.firstResponder === controller.outlineView)
  }

  @Test
  func givenNestedDisclosure_whenRestoreOrderIsResolved_thenParentsPrecedeDescendants()
    throws
  {
    let fixture = StorageTreeOutlineFixture()
    let parent = fixture.folder(
      name: "Parent",
      diskUsedBytes: 20,
      isIncomplete: false,
      hasChildren: true
    )
    let child = StorageTreeItem(
      id: UUID(),
      parentID: parent.id,
      location: parent.location.appending(
        path: "Child",
        directoryHint: .isDirectory
      ),
      name: "Child",
      kind: .folder,
      diskUsedBytes: 20,
      apparentSizeBytes: 20,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: false
    )
    let leaf = StorageTreeItem(
      id: UUID(),
      parentID: child.id,
      location: child.location.appending(path: "leaf.bin"),
      name: "leaf.bin",
      kind: .file,
      diskUsedBytes: 20,
      apparentSizeBytes: 20,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    let snapshot = StorageTreeOutlineSnapshot(
      root: fixture.root,
      pages: [
        fixture.root.id: StorageTreePage(
          parentID: fixture.root.id,
          items: [parent],
          nextOffset: nil
        ),
        parent.id: StorageTreePage(
          parentID: parent.id,
          items: [child],
          nextOffset: nil
        ),
        child.id: StorageTreePage(
          parentID: child.id,
          items: [leaf],
          nextOffset: nil
        ),
      ],
      expandedItemIDs: [fixture.root.id, parent.id, child.id],
      selectedItemID: child.id,
      renamingItemID: nil
    )

    let order = StorageTreeOutlineController.expansionRestoreOrder(
      for: snapshot
    )
    let controller = StorageTreeOutlineController()
    controller.apply(snapshot)

    #expect(order == [fixture.root.id, parent.id, child.id])
    #expect(
      controller.expandedItemIDs
        == [fixture.root.id, parent.id, child.id]
    )
    #expect(controller.selectedItemID == child.id)
  }

  @Test
  func givenPageWithNextOffset_whenLoadingRowBecomesVisible_thenParentPageIsRequestedOnce() {
    let fixture = StorageTreeOutlineFixture()
    let controller = StorageTreeOutlineController()
    var requestedParentIDs: [UUID] = []
    controller.onLoadNextPage = { parentID in
      requestedParentIDs.append(parentID)
    }
    controller.apply(fixture.snapshotWithNextPage)
    let loadingRow = controller.outlineView.numberOfRows - 1

    _ = controller.outlineView.view(
      atColumn: 0,
      row: loadingRow,
      makeIfNecessary: true
    )
    _ = controller.outlineView.view(
      atColumn: 0,
      row: loadingRow,
      makeIfNecessary: true
    )

    #expect(controller.outlineView.numberOfRows == 3)
    #expect(requestedParentIDs == [fixture.root.id])
  }

  @Test
  func givenEmptyPartialAndUnknownFolders_whenDiskUsedCellsAppear_thenLabelsRemainHonest()
    throws
  {
    let fixture = StorageTreeOutlineFixture()
    let controller = StorageTreeOutlineController()
    controller.apply(
      fixture.snapshot(
        items: [
          fixture.folder(
            name: "Empty",
            diskUsedBytes: nil,
            isIncomplete: false
          ),
          fixture.folder(
            name: "Partial",
            diskUsedBytes: 40,
            isIncomplete: true
          ),
          fixture.folder(
            name: "Unknown",
            diskUsedBytes: nil,
            isIncomplete: true
          ),
        ]
      )
    )
    #expect(
      controller.outlineView.tableColumns.map(\.identifier.rawValue)
        == ["name", "diskUsed", "statusActions"]
    )
    let nameCell =
      controller.outlineView.view(
        atColumn: 0,
        row: 1,
        makeIfNecessary: true
      ) as? NSTableCellView
    #expect(nameCell?.imageView?.image != nil)
    let diskUsedColumn = try #require(
      controller.outlineView.tableColumns.firstIndex {
        $0.identifier.rawValue == "diskUsed"
      }
    )

    #expect(
      cellText(
        in: controller,
        column: diskUsedColumn,
        row: 1
      ) == "Empty"
    )
    #expect(
      cellText(
        in: controller,
        column: diskUsedColumn,
        row: 2
      ) == "≥ 40 bytes"
    )
    #expect(
      cellText(
        in: controller,
        column: diskUsedColumn,
        row: 3
      ) == "Unavailable"
    )
  }

  @Test
  func givenFilesystemEvidence_whenStatusCellRenders_thenTextAndAccessibilityExposeStatuses()
    throws
  {
    let fixture = StorageTreeOutlineFixture()
    let controller = StorageTreeOutlineController()
    let package = StorageTreeItem(
      id: UUID(),
      parentID: fixture.root.id,
      location: fixture.root.location.appending(
        path: "Sample.app",
        directoryHint: .isDirectory
      ),
      name: "Sample.app",
      kind: .package,
      diskUsedBytes: 40,
      apparentSizeBytes: 40,
      isDiskUsedIncomplete: true,
      isApparentSizeIncomplete: true,
      hasChildren: true,
      isRoot: false,
      isShared: true,
      isHidden: true,
      isCloudOnly: true
    )
    controller.apply(fixture.snapshot(items: [package]))
    let statusColumn = try #require(
      controller.outlineView.tableColumns.firstIndex {
        $0.identifier.rawValue == "statusActions"
      }
    )
    let cell = try #require(
      controller.outlineView.view(
        atColumn: statusColumn,
        row: 1,
        makeIfNecessary: true
      ) as? NSTableCellView
    )

    #expect(
      cell.textField?.stringValue
        == "Hidden, Package, Shared, Cloud, Incomplete"
    )
    #expect(
      cell.accessibilityValue() as? String
        == "Hidden, Package, Shared, Cloud, Incomplete"
    )
    #expect(cell.toolTip?.contains("not independently reclaimable") == true)
    #expect(cell.toolTip?.contains("not downloaded") == true)
  }

  @Test
  func givenLiveItemEvidence_whenStatusIsPresented_thenTextAndAccessibilityExposeStatuses() {
    let item = StorageItemSummary(
      id: UUID(),
      location: URL(filePath: "/tmp/.Sample.app", directoryHint: .isDirectory),
      name: ".Sample.app",
      kind: .package,
      diskUsedBytes: 40,
      isShared: true,
      isHidden: true,
      isCloudOnly: true
    )

    let status = StorageStatusPresentation(item: item)

    #expect(status.text == "Hidden, Package, Shared, Cloud")
    #expect(status.accessibilityValue == "Hidden, Package, Shared, Cloud")
    #expect(status.explanation.contains("not independently reclaimable"))
    #expect(status.explanation.contains("not downloaded"))
  }

  @Test
  func givenPackageWithIndexedDescendants_whenOutlineQueriesExpansion_thenPackageRemainsLeaf() {
    let fixture = StorageTreeOutlineFixture()
    let controller = StorageTreeOutlineController()
    let package = StorageTreeItem(
      id: UUID(),
      parentID: fixture.root.id,
      location: fixture.root.location.appending(
        path: "Sample.app",
        directoryHint: .isDirectory
      ),
      name: "Sample.app",
      kind: .package,
      diskUsedBytes: 40,
      apparentSizeBytes: 40,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: false
    )
    controller.apply(fixture.snapshot(items: [package]))
    let packageNode = controller.outlineView.item(atRow: 1)!

    #expect(
      !controller.outlineView(
        controller.outlineView,
        isItemExpandable: packageNode
      )
    )
  }

  @Test
  func givenInteractiveOutline_whenDisclosureAndSelectionChange_thenStableIDsAreReported() {
    let fixture = StorageTreeOutlineFixture()
    let controller = StorageTreeOutlineController()
    var disclosureEvents: [DisclosureEvent] = []
    var selectionEvents: [UUID?] = []
    controller.onExpansionChange = { itemID, isExpanded in
      disclosureEvents.append(
        DisclosureEvent(
          itemID: itemID,
          isExpanded: isExpanded
        )
      )
    }
    controller.onSelectionChange = { itemID in
      selectionEvents.append(itemID)
    }
    controller.apply(fixture.initialSnapshot)
    let rootNode = controller.outlineView.item(atRow: 0)

    controller.outlineView.collapseItem(rootNode)
    controller.outlineView.expandItem(rootNode)
    controller.outlineView.selectRowIndexes(
      IndexSet(integer: 1),
      byExtendingSelection: false
    )

    #expect(
      disclosureEvents == [
        DisclosureEvent(
          itemID: fixture.root.id,
          isExpanded: false
        ),
        DisclosureEvent(
          itemID: fixture.root.id,
          isExpanded: true
        ),
      ]
    )
    #expect(selectionEvents.last == fixture.firstChild.id)
  }

  private func cellText(
    in controller: StorageTreeOutlineController,
    column: Int,
    row: Int
  ) -> String? {
    let cell =
      controller.outlineView.view(
        atColumn: column,
        row: row,
        makeIfNecessary: true
      ) as? NSTableCellView
    return cell?.textField?.stringValue
  }
}

private struct DisclosureEvent: Equatable {
  let itemID: UUID
  let isExpanded: Bool
}

private struct StorageTreeOutlineFixture {
  let root: StorageTreeItem
  let firstChild: StorageTreeItem
  let adjacentChild: StorageTreeItem

  init() {
    let rootID = UUID()
    let rootURL = URL(
      fileURLWithPath: "/Users/tester",
      isDirectory: true
    )
    root = StorageTreeItem(
      id: rootID,
      parentID: nil,
      location: rootURL,
      name: "tester",
      kind: .folder,
      diskUsedBytes: 30,
      apparentSizeBytes: 30,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: true,
      isRoot: true
    )
    firstChild = StorageTreeItem(
      id: UUID(),
      parentID: rootID,
      location: rootURL.appending(path: "first.bin"),
      name: "first.bin",
      kind: .file,
      diskUsedBytes: 20,
      apparentSizeBytes: 20,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    adjacentChild = StorageTreeItem(
      id: UUID(),
      parentID: rootID,
      location: rootURL.appending(path: "adjacent.bin"),
      name: "adjacent.bin",
      kind: .file,
      diskUsedBytes: 10,
      apparentSizeBytes: 10,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
  }

  var initialSnapshot: StorageTreeOutlineSnapshot {
    snapshot(items: [firstChild])
  }

  var snapshotWithAdjacentChild: StorageTreeOutlineSnapshot {
    snapshot(items: [firstChild, adjacentChild])
  }

  var snapshotWithNextPage: StorageTreeOutlineSnapshot {
    snapshot(items: [firstChild], nextOffset: 1)
  }

  func folder(
    name: String,
    diskUsedBytes: Int64?,
    isIncomplete: Bool,
    hasChildren: Bool = false
  ) -> StorageTreeItem {
    StorageTreeItem(
      id: UUID(),
      parentID: root.id,
      location: root.location.appending(
        path: name,
        directoryHint: .isDirectory
      ),
      name: name,
      kind: .folder,
      diskUsedBytes: diskUsedBytes,
      apparentSizeBytes: diskUsedBytes,
      isDiskUsedIncomplete: isIncomplete,
      isApparentSizeIncomplete: isIncomplete,
      hasChildren: hasChildren,
      isRoot: false
    )
  }

  func snapshot(
    items: [StorageTreeItem],
    nextOffset: Int? = nil
  ) -> StorageTreeOutlineSnapshot {
    StorageTreeOutlineSnapshot(
      root: root,
      pages: [
        root.id: StorageTreePage(
          parentID: root.id,
          items: items,
          nextOffset: nextOffset
        )
      ],
      expandedItemIDs: [root.id],
      selectedItemID: firstChild.id,
      renamingItemID: nil
    )
  }
}
