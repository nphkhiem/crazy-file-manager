import AppKit
import Foundation
import SwiftUI

struct StorageTreeOutlineView: NSViewRepresentable {
  let session: ExplorerSession

  func makeNSView(context: Context) -> StorageTreeOutlineController {
    let controller = StorageTreeOutlineController()
    connect(controller)
    return controller
  }

  func updateNSView(
    _ controller: StorageTreeOutlineController,
    context: Context
  ) {
    connect(controller)
    controller.apply(
      StorageTreeOutlineSnapshot(
        root: session.treeRoot,
        pages: session.treePages,
        expandedItemIDs: session.expandedTreeItemIDs,
        selectedItemID: session.selectedTreeItemID
      )
    )
  }

  static func dismantleNSView(
    _ controller: StorageTreeOutlineController,
    coordinator: Void
  ) {
    controller.onExpansionChange = nil
    controller.onSelectionChange = nil
    controller.onLoadNextPage = nil
  }

  private func connect(
    _ controller: StorageTreeOutlineController
  ) {
    controller.onExpansionChange = { [weak session] itemID, expanded in
      session?.setTreeItem(itemID, expanded: expanded)
    }
    controller.onSelectionChange = { [weak session] itemID in
      session?.selectTreeItem(itemID)
    }
    controller.onLoadNextPage = { [weak session] parentID in
      Task { @MainActor in
        await session?.loadNextTreePage(for: parentID)
      }
    }
  }
}

struct StorageTreeOutlineSnapshot: Equatable {
  let root: StorageTreeItem?
  let pages: [UUID: StorageTreePage]
  let expandedItemIDs: Set<UUID>
  let selectedItemID: UUID?
}

@MainActor
final class StorageTreeOutlineController: NSView {
  let outlineView = NSOutlineView()
  var onLoadNextPage: ((UUID) -> Void)?
  var onExpansionChange: ((UUID, Bool) -> Void)?
  var onSelectionChange: ((UUID?) -> Void)?

  private let scrollView = NSScrollView()
  private var snapshot = StorageTreeOutlineSnapshot(
    root: nil,
    pages: [:],
    expandedItemIDs: [],
    selectedItemID: nil
  )
  private var nodesByID: [UUID: StorageTreeOutlineNode] = [:]
  private var loadingNodesByParentID: [UUID: StorageTreeOutlineLoadingNode] = [:]
  private var requestedPages: Set<StorageTreePageRequest> = []
  private var isApplyingSnapshot = false

  var expandedItemIDs: Set<UUID> {
    Set(
      nodesByID.compactMap { id, node in
        outlineView.isItemExpanded(node) ? id : nil
      }
    )
  }

  var selectedItemID: UUID? {
    guard
      outlineView.selectedRow >= 0,
      let node = outlineView.item(
        atRow: outlineView.selectedRow
      ) as? StorageTreeOutlineNode
    else {
      return nil
    }
    return node.item.id
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configureViews()
  }

  convenience init() {
    self.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func apply(_ snapshot: StorageTreeOutlineSnapshot) {
    let hadOutlineFocus = window?.firstResponder === outlineView
    isApplyingSnapshot = true
    defer {
      isApplyingSnapshot = false
    }
    self.snapshot = snapshot
    synchronizeNodes(with: snapshot)
    outlineView.reloadData()
    restoreExpandedItems()
    restoreSelection(snapshot.selectedItemID)
    if hadOutlineFocus {
      window?.makeFirstResponder(outlineView)
    }
  }

  static func expansionRestoreOrder(
    for snapshot: StorageTreeOutlineSnapshot
  ) -> [UUID] {
    guard
      let rootID = snapshot.root?.id,
      snapshot.expandedItemIDs.contains(rootID)
    else {
      return []
    }

    var order = [rootID]
    var index = 0
    while index < order.count {
      let parentID = order[index]
      index += 1
      let expandedChildren =
        snapshot.pages[parentID]?.items.filter {
          snapshot.expandedItemIDs.contains($0.id)
        } ?? []
      order.append(contentsOf: expandedChildren.map(\.id))
    }
    return order
  }

  private func configureViews() {
    let nameColumn = NSTableColumn(
      identifier: NSUserInterfaceItemIdentifier("name")
    )
    nameColumn.title = "Name"
    nameColumn.minWidth = 240
    outlineView.addTableColumn(nameColumn)

    let diskUsedColumn = NSTableColumn(
      identifier: NSUserInterfaceItemIdentifier("diskUsed")
    )
    diskUsedColumn.title = "Disk Used"
    diskUsedColumn.minWidth = 120
    diskUsedColumn.width = 150
    diskUsedColumn.maxWidth = 180
    outlineView.addTableColumn(diskUsedColumn)

    let statusActionsColumn = NSTableColumn(
      identifier: NSUserInterfaceItemIdentifier("statusActions")
    )
    statusActionsColumn.title = "Status / Actions"
    statusActionsColumn.minWidth = 120
    statusActionsColumn.width = 140
    outlineView.addTableColumn(statusActionsColumn)

    outlineView.outlineTableColumn = nameColumn
    outlineView.headerView = NSTableHeaderView()
    outlineView.usesAlternatingRowBackgroundColors = true
    outlineView.rowSizeStyle = .default
    outlineView.dataSource = self
    outlineView.delegate = self

    scrollView.documentView = outlineView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  private func synchronizeNodes(
    with snapshot: StorageTreeOutlineSnapshot
  ) {
    let items =
      [snapshot.root].compactMap(\.self)
      + snapshot.pages.values.flatMap(\.items)
    let itemIDs = Set(items.map(\.id))
    nodesByID = nodesByID.filter { itemIDs.contains($0.key) }
    for item in items {
      if let node = nodesByID[item.id] {
        node.item = item
      } else {
        nodesByID[item.id] = StorageTreeOutlineNode(item: item)
      }
    }

    let loadingPages = snapshot.pages.values.compactMap { page in
      page.nextOffset.map {
        StorageTreePageRequest(parentID: page.parentID, offset: $0)
      }
    }
    requestedPages.formIntersection(loadingPages)
    let loadingParentIDs = Set(loadingPages.map(\.parentID))
    loadingNodesByParentID = loadingNodesByParentID.filter {
      loadingParentIDs.contains($0.key)
    }
    for request in loadingPages {
      if let node = loadingNodesByParentID[request.parentID] {
        node.offset = request.offset
      } else {
        loadingNodesByParentID[request.parentID] =
          StorageTreeOutlineLoadingNode(
            parentID: request.parentID,
            offset: request.offset
          )
      }
    }
  }

  private func restoreExpandedItems() {
    for itemID in Self.expansionRestoreOrder(for: snapshot) {
      if let node = nodesByID[itemID] {
        outlineView.expandItem(node)
      }
    }
  }

  private func restoreSelection(_ itemID: UUID?) {
    guard
      let itemID,
      let node = nodesByID[itemID]
    else {
      outlineView.deselectAll(nil)
      return
    }
    let row = outlineView.row(forItem: node)
    guard row >= 0 else {
      outlineView.deselectAll(nil)
      return
    }
    outlineView.selectRowIndexes(
      IndexSet(integer: row),
      byExtendingSelection: false
    )
  }
}

extension StorageTreeOutlineController: NSOutlineViewDataSource {
  func outlineView(
    _ outlineView: NSOutlineView,
    numberOfChildrenOfItem item: Any?
  ) -> Int {
    guard let node = item as? StorageTreeOutlineNode else {
      return snapshot.root == nil ? 0 : 1
    }
    guard let page = snapshot.pages[node.item.id] else {
      return 0
    }
    return page.items.count + (page.nextOffset == nil ? 0 : 1)
  }

  func outlineView(
    _ outlineView: NSOutlineView,
    child index: Int,
    ofItem item: Any?
  ) -> Any {
    if let node = item as? StorageTreeOutlineNode {
      let page = snapshot.pages[node.item.id]!
      if index < page.items.count {
        let child = page.items[index]
        return nodesByID[child.id]!
      }
      return loadingNodesByParentID[node.item.id]!
    }
    return nodesByID[snapshot.root!.id]!
  }

  func outlineView(
    _ outlineView: NSOutlineView,
    isItemExpandable item: Any
  ) -> Bool {
    guard let node = item as? StorageTreeOutlineNode else {
      return false
    }
    return node.item.kind == .folder && node.item.hasChildren
  }
}

extension StorageTreeOutlineController: NSOutlineViewDelegate {
  func outlineViewSelectionDidChange(_ notification: Notification) {
    guard !isApplyingSnapshot else {
      return
    }
    onSelectionChange?(selectedItemID)
  }

  func outlineViewItemDidExpand(_ notification: Notification) {
    reportExpansionChange(notification, isExpanded: true)
  }

  func outlineViewItemDidCollapse(_ notification: Notification) {
    reportExpansionChange(notification, isExpanded: false)
  }

  func outlineView(
    _ outlineView: NSOutlineView,
    viewFor tableColumn: NSTableColumn?,
    item: Any
  ) -> NSView? {
    if let loadingNode = item as? StorageTreeOutlineLoadingNode {
      if tableColumn?.identifier.rawValue == "name" {
        requestNextPageIfNeeded(for: loadingNode)
        return loadingCell(in: outlineView)
      }
      return textCell(
        in: outlineView,
        identifier: "emptyLoadingCell",
        text: "",
        alignment: .left
      )
    }
    guard
      let node = item as? StorageTreeOutlineNode,
      let columnIdentifier = tableColumn?.identifier.rawValue
    else {
      return nil
    }
    switch columnIdentifier {
    case "name":
      return nameCell(for: node.item, in: outlineView)
    case "diskUsed":
      return diskUsedCell(for: node.item, in: outlineView)
    case "statusActions":
      return statusActionsCell(for: node.item, in: outlineView)
    default:
      return nil
    }
  }

  private func nameCell(
    for item: StorageTreeItem,
    in outlineView: NSOutlineView
  ) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("nameCell")
    let cell: NSTableCellView
    if let reusedCell = outlineView.makeView(
      withIdentifier: identifier,
      owner: self
    ) as? NSTableCellView {
      cell = reusedCell
    } else {
      cell = NSTableCellView()
      cell.identifier = identifier
      let imageView = NSImageView()
      imageView.imageScaling = .scaleProportionallyDown
      imageView.contentTintColor = .secondaryLabelColor
      imageView.translatesAutoresizingMaskIntoConstraints = false
      let textField = NSTextField(labelWithString: "")
      textField.lineBreakMode = .byTruncatingMiddle
      textField.translatesAutoresizingMaskIntoConstraints = false
      cell.imageView = imageView
      cell.textField = textField
      cell.addSubview(imageView)
      cell.addSubview(textField)
      NSLayoutConstraint.activate([
        imageView.leadingAnchor.constraint(
          equalTo: cell.leadingAnchor,
          constant: 4
        ),
        imageView.centerYAnchor.constraint(
          equalTo: cell.centerYAnchor
        ),
        imageView.widthAnchor.constraint(equalToConstant: 16),
        imageView.heightAnchor.constraint(equalToConstant: 16),
        textField.leadingAnchor.constraint(
          equalTo: imageView.trailingAnchor,
          constant: 6
        ),
        textField.trailingAnchor.constraint(
          equalTo: cell.trailingAnchor,
          constant: -4
        ),
        textField.centerYAnchor.constraint(
          equalTo: cell.centerYAnchor
        ),
      ])
    }
    cell.imageView?.image = NSImage(
      systemSymbolName: systemImageName(for: item.kind),
      accessibilityDescription: nil
    )
    cell.textField?.stringValue = item.name
    cell.toolTip = item.location.path(percentEncoded: false)
    cell.setAccessibilityLabel(item.name)
    cell.setAccessibilityValue(
      item.location.path(percentEncoded: false)
    )
    return cell
  }

  private func diskUsedCell(
    for item: StorageTreeItem,
    in outlineView: NSOutlineView
  ) -> NSTableCellView {
    let text = diskUsedText(for: item)
    let cell = textCell(
      in: outlineView,
      identifier: "diskUsedCell",
      text: text,
      alignment: .right
    )
    cell.textField?.font = NSFont.monospacedDigitSystemFont(
      ofSize: NSFont.systemFontSize,
      weight: .regular
    )
    cell.setAccessibilityLabel("Disk Used")
    cell.setAccessibilityValue(diskUsedAccessibilityValue(for: item))
    return cell
  }

  private func statusActionsCell(
    for item: StorageTreeItem,
    in outlineView: NSOutlineView
  ) -> NSTableCellView {
    let text = item.isDiskUsedIncomplete ? "Incomplete" : ""
    let cell = textCell(
      in: outlineView,
      identifier: "statusActionsCell",
      text: text,
      alignment: .left
    )
    cell.textField?.textColor = .secondaryLabelColor
    return cell
  }

  private func textCell(
    in outlineView: NSOutlineView,
    identifier identifierText: String,
    text: String,
    alignment: NSTextAlignment
  ) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier(identifierText)
    let cell: NSTableCellView
    if let reusedCell = outlineView.makeView(
      withIdentifier: identifier,
      owner: self
    ) as? NSTableCellView {
      cell = reusedCell
    } else {
      cell = NSTableCellView()
      cell.identifier = identifier
      let textField = NSTextField(labelWithString: "")
      textField.lineBreakMode = .byTruncatingTail
      textField.translatesAutoresizingMaskIntoConstraints = false
      cell.textField = textField
      cell.addSubview(textField)
      NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(
          equalTo: cell.leadingAnchor,
          constant: 4
        ),
        textField.trailingAnchor.constraint(
          equalTo: cell.trailingAnchor,
          constant: -4
        ),
        textField.centerYAnchor.constraint(
          equalTo: cell.centerYAnchor
        ),
      ])
    }
    cell.textField?.alignment = alignment
    cell.textField?.stringValue = text
    return cell
  }

  private func diskUsedText(for item: StorageTreeItem) -> String {
    guard let diskUsedBytes = item.diskUsedBytes else {
      if item.kind == .folder,
        !item.hasChildren,
        !item.isDiskUsedIncomplete
      {
        return "Empty"
      }
      return "Unavailable"
    }
    let formattedBytes = diskUsedBytes.formatted(
      .byteCount(style: .file)
    )
    return item.isDiskUsedIncomplete
      ? "≥ \(formattedBytes)"
      : formattedBytes
  }

  private func diskUsedAccessibilityValue(
    for item: StorageTreeItem
  ) -> String {
    let text = diskUsedText(for: item)
    if item.isDiskUsedIncomplete, item.diskUsedBytes != nil {
      return "Incomplete, at least \(text.dropFirst(2))"
    }
    if text == "Empty" {
      return "Empty folder"
    }
    return text
  }

  private func systemImageName(
    for kind: StorageItemKind
  ) -> String {
    switch kind {
    case .file:
      "doc"
    case .folder:
      "folder.fill"
    case .symbolicLink:
      "arrow.trianglehead.branch"
    case .other:
      "questionmark.square.dashed"
    case .package:
      "shippingbox.fill"
    }
  }

  private func loadingCell(
    in outlineView: NSOutlineView
  ) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("loadingCell")
    if let cell = outlineView.makeView(
      withIdentifier: identifier,
      owner: self
    ) as? NSTableCellView {
      return cell
    }

    let cell = NSTableCellView()
    cell.identifier = identifier
    let textField = NSTextField(labelWithString: "Loading more…")
    textField.textColor = .secondaryLabelColor
    textField.translatesAutoresizingMaskIntoConstraints = false
    cell.textField = textField
    cell.addSubview(textField)
    NSLayoutConstraint.activate([
      textField.leadingAnchor.constraint(
        equalTo: cell.leadingAnchor,
        constant: 4
      ),
      textField.trailingAnchor.constraint(
        lessThanOrEqualTo: cell.trailingAnchor,
        constant: -4
      ),
      textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  private func requestNextPageIfNeeded(
    for node: StorageTreeOutlineLoadingNode
  ) {
    let request = StorageTreePageRequest(
      parentID: node.parentID,
      offset: node.offset
    )
    guard requestedPages.insert(request).inserted else {
      return
    }
    onLoadNextPage?(node.parentID)
  }

  private func reportExpansionChange(
    _ notification: Notification,
    isExpanded: Bool
  ) {
    guard
      !isApplyingSnapshot,
      let node = notification.userInfo?["NSObject"]
        as? StorageTreeOutlineNode
    else {
      return
    }
    onExpansionChange?(node.item.id, isExpanded)
  }
}

private final class StorageTreeOutlineNode: NSObject {
  var item: StorageTreeItem

  init(item: StorageTreeItem) {
    self.item = item
  }
}

private final class StorageTreeOutlineLoadingNode: NSObject {
  let parentID: UUID
  var offset: Int

  init(parentID: UUID, offset: Int) {
    self.parentID = parentID
    self.offset = offset
  }
}

private struct StorageTreePageRequest: Hashable {
  let parentID: UUID
  let offset: Int
}
