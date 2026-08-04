import AppKit
import Foundation
import Testing

@testable import CrazyFileManager

@MainActor
@Suite("All Items Table View")
struct AllItemsTableViewTests {
  @Test
  func givenRows_whenSnapshotIsApplied_thenNameAndDiskUsedCellsRenderAndSelectionIsRestored() {
    let fixture = AllItemsTableFixture()
    let controller = AllItemsTableController()

    controller.apply(fixture.snapshot(rows: [fixture.alpha, fixture.beta]))

    #expect(
      controller.tableView.tableColumns.map(\.identifier.rawValue)
        == ["name", "diskUsed", "statusActions"]
    )
    let nameCell =
      controller.tableView.view(
        atColumn: 0,
        row: 0,
        makeIfNecessary: true
      ) as? NSTableCellView
    #expect(nameCell?.textField?.stringValue == "alpha.bin")
    #expect(nameCell?.imageView?.image != nil)
    let diskUsedColumn = try! #require(
      controller.tableView.tableColumns.firstIndex { $0.identifier.rawValue == "diskUsed" }
    )
    let diskUsedCell =
      controller.tableView.view(
        atColumn: diskUsedColumn,
        row: 1,
        makeIfNecessary: true
      ) as? NSTableCellView
    #expect(diskUsedCell?.textField?.stringValue == "20 bytes")
    #expect(controller.selectedItemIDs == [fixture.alpha.id])
  }

  @Test
  func givenAnOptionalColumnBecomesVisible_whenSnapshotIsApplied_thenTheColumnIsAddedAndRemoved() {
    let fixture = AllItemsTableFixture()
    let controller = AllItemsTableController()
    controller.apply(fixture.snapshot(rows: [fixture.alpha]))
    #expect(
      !controller.tableView.tableColumns.map(\.identifier.rawValue).contains("path")
    )

    controller.apply(
      fixture.snapshot(rows: [fixture.alpha], visibleOptionalColumns: [.path])
    )
    #expect(controller.tableView.tableColumns.map(\.identifier.rawValue).contains("path"))

    controller.apply(fixture.snapshot(rows: [fixture.alpha]))
    #expect(
      !controller.tableView.tableColumns.map(\.identifier.rawValue).contains("path")
    )
  }

  @Test
  func givenADiskUsedAscendingSortDescriptor_whenItChanges_thenOnSortChangeReportsIt() {
    let fixture = AllItemsTableFixture()
    let controller = AllItemsTableController()
    controller.apply(fixture.snapshot(rows: [fixture.alpha, fixture.beta]))
    var reportedSort: AllItemsSort?
    controller.onSortChange = { sort in
      reportedSort = sort
    }

    controller.tableView.sortDescriptors = [
      NSSortDescriptor(key: "diskUsed", ascending: true)
    ]

    #expect(reportedSort == AllItemsSort(field: .diskUsed, direction: .ascending))
  }

  @Test
  func givenPageWithNextOffset_whenLoadingRowBecomesVisible_thenNextPageIsRequestedOnce() {
    let fixture = AllItemsTableFixture()
    let controller = AllItemsTableController()
    var requestCount = 0
    controller.onLoadNextPage = {
      requestCount += 1
    }
    controller.apply(fixture.snapshot(rows: [fixture.alpha], nextOffset: 1))
    let loadingRow = controller.tableView.numberOfRows - 1

    _ = controller.tableView.view(atColumn: 0, row: loadingRow, makeIfNecessary: true)
    _ = controller.tableView.view(atColumn: 0, row: loadingRow, makeIfNecessary: true)

    #expect(controller.tableView.numberOfRows == 2)
    #expect(requestCount == 1)
  }

  @Test
  func givenHeaderMenu_whenOpenedAndAnItemIsSelected_thenCheckStatesMatchAndToggleFires() {
    let fixture = AllItemsTableFixture()
    let controller = AllItemsTableController()
    controller.apply(
      fixture.snapshot(rows: [fixture.alpha], visibleOptionalColumns: [.modifiedAt])
    )
    let menu = try! #require(controller.tableView.headerView?.menu)
    menu.delegate?.menuNeedsUpdate?(menu)
    let modifiedAtItem = try! #require(
      menu.items.first { ($0.representedObject as? AllItemsOptionalColumn) == .modifiedAt }
    )
    let pathItem = try! #require(
      menu.items.first { ($0.representedObject as? AllItemsOptionalColumn) == .path }
    )
    #expect(modifiedAtItem.state == .on)
    #expect(pathItem.state == .off)

    var toggledColumn: AllItemsOptionalColumn?
    controller.onToggleOptionalColumn = { column in
      toggledColumn = column
    }
    _ = pathItem.target?.perform(pathItem.action, with: pathItem)

    #expect(toggledColumn == .path)
  }

  @Test
  func givenASingleSelectedRow_whenReturnKeyIsPressed_thenOnBeginRenameFiresWithItsID() {
    let fixture = AllItemsTableFixture()
    let controller = AllItemsTableController()
    controller.apply(fixture.snapshot(rows: [fixture.alpha, fixture.beta]))
    controller.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    var beganRenameItemID: UUID?
    controller.onBeginRename = { itemID in
      beganRenameItemID = itemID
    }

    controller.tableView.onReturnKeyPressed?()

    #expect(beganRenameItemID == fixture.beta.id)
  }

  @Test
  func givenAnEligibleRow_whenTrashButtonIsTapped_thenOnBeginTrashFiresWithItsID() throws {
    let fixture = AllItemsTableFixture()
    let controller = AllItemsTableController()
    controller.apply(
      fixture.snapshot(
        rows: [fixture.alpha],
        capabilities: [
          fixture.alpha.id: ItemCapability(
            canRename: true,
            cannotRenameReason: nil,
            canTrash: true,
            cannotTrashReason: nil
          )
        ]
      )
    )
    let statusColumn = try #require(
      controller.tableView.tableColumns.firstIndex { $0.identifier.rawValue == "statusActions" }
    )
    let cell = try #require(
      controller.tableView.view(atColumn: statusColumn, row: 0, makeIfNecessary: true)
        as? NSTableCellView
    )
    let trashButton = try #require(cell.subviews.compactMap { $0 as? NSButton }.first)
    var trashedItemID: UUID?
    controller.onBeginTrash = { itemID in
      trashedItemID = itemID
    }

    _ = trashButton.target?.perform(trashButton.action, with: trashButton)

    #expect(trashedItemID == fixture.alpha.id)
  }

  @Test
  func givenNoRowsAndNoActiveQuery_whenApplied_thenTheNoItemsStateShows() {
    let fixture = AllItemsTableFixture()
    let controller = AllItemsTableController()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = controller

    controller.apply(fixture.snapshot(rows: [], hasActiveQuery: false))

    #expect(controller.emptyStateText == "No items to show")
    #expect(controller.isEmptyStateVisible)
  }

  @Test
  func givenNoRowsAndAnActiveQuery_whenApplied_thenTheNoMatchesStateShows() {
    let fixture = AllItemsTableFixture()
    let controller = AllItemsTableController()

    controller.apply(fixture.snapshot(rows: [], hasActiveQuery: true))

    #expect(controller.emptyStateText == "No matching items")
    #expect(controller.isEmptyStateVisible)
  }

  @Test
  func givenRows_whenApplied_thenTheEmptyStateIsHidden() {
    let fixture = AllItemsTableFixture()
    let controller = AllItemsTableController()

    controller.apply(fixture.snapshot(rows: [fixture.alpha]))

    #expect(!controller.isEmptyStateVisible)
  }
}

private struct AllItemsTableFixture {
  let alpha: StorageTreeItem
  let beta: StorageTreeItem

  init() {
    let rootURL = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    alpha = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: rootURL.appending(path: "alpha.bin"),
      name: "alpha.bin",
      kind: .file,
      diskUsedBytes: 30,
      apparentSizeBytes: 30,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
    beta = StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: rootURL.appending(path: "beta.bin"),
      name: "beta.bin",
      kind: .file,
      diskUsedBytes: 20,
      apparentSizeBytes: 20,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false
    )
  }

  func snapshot(
    rows: [StorageTreeItem],
    nextOffset: Int? = nil,
    selectedItemIDs: Set<UUID>? = nil,
    renamingItemID: UUID? = nil,
    capabilities: [UUID: ItemCapability] = [:],
    visibleOptionalColumns: Set<AllItemsOptionalColumn> = [],
    sort: AllItemsSort = AllItemsSort(),
    hasActiveQuery: Bool = false
  ) -> AllItemsRowsSnapshot {
    AllItemsRowsSnapshot(
      rows: rows,
      nextOffset: nextOffset,
      selectedItemIDs: selectedItemIDs ?? (rows.first.map { [$0.id] } ?? []),
      renamingItemID: renamingItemID,
      capabilities: capabilities,
      visibleOptionalColumns: visibleOptionalColumns,
      sort: sort,
      hasActiveQuery: hasActiveQuery
    )
  }
}
