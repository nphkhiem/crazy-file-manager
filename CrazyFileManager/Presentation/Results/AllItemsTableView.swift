import AppKit
import Foundation
import SwiftUI

struct AllItemsRowsSnapshot: Equatable {
  let rows: [StorageTreeItem]
  let nextOffset: Int?
  let selectedItemIDs: Set<UUID>
  let renamingItemID: UUID?
  let capabilities: [UUID: ItemCapability]
  let visibleOptionalColumns: Set<AllItemsOptionalColumn>
  let sort: AllItemsSort
  let hasActiveQuery: Bool
  let isLoading: Bool
}

@MainActor
final class RenameCapableTableView: NSTableView {
  private static let returnKeyCode: UInt16 = 36
  private static let deleteKeyCode: UInt16 = 51

  var onReturnKeyPressed: (() -> Void)?
  var onCommandDeleteKeyPressed: (() -> Void)?

  override func keyDown(with event: NSEvent) {
    if event.keyCode == Self.returnKeyCode, selectedRow >= 0, currentEditor() == nil {
      onReturnKeyPressed?()
      return
    }
    if event.keyCode == Self.deleteKeyCode, event.modifierFlags.contains(.command),
      selectedRow >= 0, currentEditor() == nil
    {
      onCommandDeleteKeyPressed?()
      return
    }
    super.keyDown(with: event)
  }
}

@MainActor
final class AllItemsTableController: NSView {
  let tableView = RenameCapableTableView()
  var onSelectionChange: ((Set<UUID>) -> Void)?
  var onLoadNextPage: (() -> Void)?
  var onBeginRename: ((UUID) -> Void)?
  var onRenameProposalChange: ((String) -> Void)?
  var onRenameCommit: (() -> Void)?
  var onRenameCancel: (() -> Void)?
  var onBeginTrash: ((UUID) -> Void)?
  var onSortChange: ((AllItemsSort) -> Void)?
  var onToggleOptionalColumn: ((AllItemsOptionalColumn) -> Void)?

  private let scrollView = NSScrollView()
  private let emptyStateContainer = NSView()
  private let emptyStateImageView = NSImageView()
  private let emptyStateTextField = NSTextField(labelWithString: "")
  private var snapshot = AllItemsRowsSnapshot(
    rows: [],
    nextOffset: nil,
    selectedItemIDs: [],
    renamingItemID: nil,
    capabilities: [:],
    visibleOptionalColumns: [],
    sort: AllItemsSort(),
    hasActiveQuery: false,
    isLoading: false
  )
  private var requestedNextPageOffset: Int?
  private var isApplyingSnapshot = false
  private var headerMenuItemsByColumn: [AllItemsOptionalColumn: NSMenuItem] = [:]

  private static let optionalColumnOrder: [AllItemsOptionalColumn] = [
    .path, .modifiedAt, .apparentSize,
  ]

  var selectedItemIDs: Set<UUID> {
    Set(
      tableView.selectedRowIndexes.compactMap { row -> UUID? in
        guard row < snapshot.rows.count else { return nil }
        return snapshot.rows[row].id
      }
    )
  }

  var isEmptyStateVisible: Bool {
    !emptyStateContainer.isHidden
  }

  var emptyStateText: String {
    emptyStateTextField.stringValue
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

  func apply(_ snapshot: AllItemsRowsSnapshot) {
    let hadTableFocus = window?.firstResponder === tableView
    let wasRenaming = self.snapshot.renamingItemID != nil
    isApplyingSnapshot = true
    defer {
      isApplyingSnapshot = false
    }
    let previousOffset = self.snapshot.nextOffset
    self.snapshot = snapshot
    if snapshot.nextOffset != previousOffset {
      requestedNextPageOffset = nil
    }
    synchronizeOptionalColumns()
    tableView.reloadData()
    restoreSelection(snapshot.selectedItemIDs)
    updateRenamingState(snapshot.renamingItemID)
    if hadTableFocus || wasRenaming, snapshot.renamingItemID == nil {
      window?.makeFirstResponder(tableView)
    }
    updateEmptyState()
  }

  private func updateEmptyState() {
    let isEmpty = snapshot.rows.isEmpty && snapshot.nextOffset == nil && !snapshot.isLoading
    emptyStateContainer.isHidden = !isEmpty
    guard isEmpty else {
      return
    }
    if snapshot.hasActiveQuery {
      emptyStateImageView.image = NSImage(
        systemSymbolName: "magnifyingglass",
        accessibilityDescription: nil
      )
      emptyStateTextField.stringValue = "No matching items"
    } else {
      emptyStateImageView.image = NSImage(
        systemSymbolName: "square.grid.2x2",
        accessibilityDescription: nil
      )
      emptyStateTextField.stringValue = "No items to show"
    }
  }

  private func updateRenamingState(_ renamingItemID: UUID?) {
    guard
      let renamingItemID,
      let row = snapshot.rows.firstIndex(where: { $0.id == renamingItemID }),
      let nameColumnIndex = tableView.tableColumns.firstIndex(where: {
        $0.identifier.rawValue == "name"
      })
    else {
      return
    }
    tableView.editColumn(nameColumnIndex, row: row, with: nil, select: true)
    if let fieldEditor = tableView.currentEditor() {
      let basename = (snapshot.rows[row].name as NSString).deletingPathExtension
      fieldEditor.selectedRange = NSRange(location: 0, length: (basename as NSString).length)
    }
  }

  private func restoreSelection(_ itemIDs: Set<UUID>) {
    let indexes = IndexSet(
      snapshot.rows.enumerated().compactMap { index, item in
        itemIDs.contains(item.id) ? index : nil
      }
    )
    guard !indexes.isEmpty else {
      tableView.deselectAll(nil)
      return
    }
    tableView.selectRowIndexes(indexes, byExtendingSelection: false)
  }

  private func configureViews() {
    let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    nameColumn.title = "Name"
    nameColumn.minWidth = 240
    nameColumn.headerCell.alignment = .left
    nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
    tableView.addTableColumn(nameColumn)

    let diskUsedColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diskUsed"))
    diskUsedColumn.title = "Disk Used"
    diskUsedColumn.minWidth = 120
    diskUsedColumn.width = 150
    diskUsedColumn.maxWidth = 180
    diskUsedColumn.headerCell.alignment = .center
    diskUsedColumn.sortDescriptorPrototype = NSSortDescriptor(key: "diskUsed", ascending: false)
    tableView.addTableColumn(diskUsedColumn)

    let statusActionsColumn = NSTableColumn(
      identifier: NSUserInterfaceItemIdentifier("statusActions")
    )
    statusActionsColumn.title = "Status / Actions"
    statusActionsColumn.minWidth = 120
    statusActionsColumn.width = 140
    statusActionsColumn.headerCell.alignment = .right
    tableView.addTableColumn(statusActionsColumn)

    tableView.headerView = NSTableHeaderView()
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.rowSizeStyle = .default
    tableView.dataSource = self
    tableView.delegate = self
    tableView.allowsMultipleSelection = true
    tableView.setAccessibilityIdentifier("allItemsTable")
    tableView.onReturnKeyPressed = { [weak self] in
      guard let self, selectedItemIDs.count == 1, let itemID = selectedItemIDs.first else {
        return
      }
      onBeginRename?(itemID)
    }
    tableView.onCommandDeleteKeyPressed = { [weak self] in
      guard
        let self, selectedItemIDs.count == 1, let itemID = selectedItemIDs.first,
        snapshot.capabilities[itemID]?.canTrash == true
      else {
        return
      }
      onBeginTrash?(itemID)
    }
    tableView.target = self
    tableView.doubleAction = #selector(handleDoubleClick)
    tableView.sortDescriptors = [NSSortDescriptor(key: "diskUsed", ascending: false)]

    let headerMenu = NSMenu()
    headerMenu.delegate = self
    for column in Self.optionalColumnOrder {
      let item = NSMenuItem(
        title: Self.title(for: column),
        action: #selector(handleOptionalColumnMenuItemSelected(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = column
      headerMenu.addItem(item)
      headerMenuItemsByColumn[column] = item
    }
    tableView.headerView?.menu = headerMenu

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    emptyStateImageView.contentTintColor = .tertiaryLabelColor
    emptyStateImageView.translatesAutoresizingMaskIntoConstraints = false
    emptyStateTextField.textColor = .secondaryLabelColor
    emptyStateTextField.translatesAutoresizingMaskIntoConstraints = false
    emptyStateContainer.translatesAutoresizingMaskIntoConstraints = false
    emptyStateContainer.isHidden = true
    emptyStateContainer.addSubview(emptyStateImageView)
    emptyStateContainer.addSubview(emptyStateTextField)
    NSLayoutConstraint.activate([
      emptyStateImageView.centerXAnchor.constraint(equalTo: emptyStateContainer.centerXAnchor),
      emptyStateImageView.topAnchor.constraint(equalTo: emptyStateContainer.topAnchor),
      emptyStateImageView.widthAnchor.constraint(equalToConstant: 32),
      emptyStateImageView.heightAnchor.constraint(equalToConstant: 32),
      emptyStateTextField.topAnchor.constraint(
        equalTo: emptyStateImageView.bottomAnchor,
        constant: 8
      ),
      emptyStateTextField.centerXAnchor.constraint(equalTo: emptyStateContainer.centerXAnchor),
      emptyStateTextField.bottomAnchor.constraint(equalTo: emptyStateContainer.bottomAnchor),
    ])

    addSubview(scrollView)
    addSubview(emptyStateContainer)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      emptyStateContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
      emptyStateContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  private func synchronizeOptionalColumns() {
    for column in Self.optionalColumnOrder {
      let identifier = NSUserInterfaceItemIdentifier(Self.identifier(for: column))
      let isVisible = snapshot.visibleOptionalColumns.contains(column)
      let existingIndex = tableView.tableColumns.firstIndex { $0.identifier == identifier }
      if isVisible, existingIndex == nil {
        let tableColumn = NSTableColumn(identifier: identifier)
        tableColumn.title = Self.title(for: column)
        tableColumn.minWidth = 100
        tableColumn.headerCell.alignment = .left
        tableColumn.sortDescriptorPrototype = NSSortDescriptor(
          key: Self.sortKey(for: column),
          ascending: true
        )
        tableView.addTableColumn(tableColumn)
      } else if !isVisible, existingIndex != nil {
        tableView.removeTableColumn(tableView.tableColumns[existingIndex!])
      }
      headerMenuItemsByColumn[column]?.state = isVisible ? .on : .off
    }
  }

  @objc
  private func handleOptionalColumnMenuItemSelected(_ sender: NSMenuItem) {
    guard let column = sender.representedObject as? AllItemsOptionalColumn else {
      return
    }
    onToggleOptionalColumn?(column)
  }

  @objc
  private func handleDoubleClick() {
    guard
      tableView.clickedColumn
        == tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("name")),
      tableView.clickedRow >= 0,
      tableView.clickedRow < snapshot.rows.count
    else {
      return
    }
    onBeginRename?(snapshot.rows[tableView.clickedRow].id)
  }

  fileprivate static func title(for column: AllItemsOptionalColumn) -> String {
    switch column {
    case .path: "Path"
    case .modifiedAt: "Modified Date"
    case .apparentSize: "Apparent Size"
    }
  }

  fileprivate static func identifier(for column: AllItemsOptionalColumn) -> String {
    switch column {
    case .path: "path"
    case .modifiedAt: "modifiedAt"
    case .apparentSize: "apparentSize"
    }
  }

  fileprivate static func sortKey(for column: AllItemsOptionalColumn) -> String {
    identifier(for: column)
  }

  fileprivate static func sortField(forKey key: String) -> AllItemsSortField? {
    switch key {
    case "name": .name
    case "diskUsed": .diskUsed
    case "path": .path
    case "modifiedAt": .modifiedAt
    case "apparentSize": .apparentSize
    default: nil
    }
  }
}

extension AllItemsTableController: NSTextFieldDelegate {
  func controlTextDidChange(_ notification: Notification) {
    guard let textField = notification.object as? NSTextField else {
      return
    }
    onRenameProposalChange?(textField.stringValue)
  }

  func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
      onRenameCommit?()
      return true
    }
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      onRenameCancel?()
      return true
    }
    return false
  }
}

extension AllItemsTableController: NSMenuDelegate {
  func menuNeedsUpdate(_ menu: NSMenu) {
    for column in Self.optionalColumnOrder {
      headerMenuItemsByColumn[column]?.state =
        snapshot.visibleOptionalColumns.contains(column) ? .on : .off
    }
  }
}

extension AllItemsTableController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int {
    snapshot.rows.count + (snapshot.nextOffset == nil ? 0 : 1)
  }
}

extension AllItemsTableController: NSTableViewDelegate {
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !isApplyingSnapshot else {
      return
    }
    onSelectionChange?(selectedItemIDs)
  }

  func tableView(
    _ tableView: NSTableView,
    sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
  ) {
    guard
      let descriptor = tableView.sortDescriptors.first,
      let key = descriptor.key,
      let field = Self.sortField(forKey: key)
    else {
      return
    }
    onSortChange?(
      AllItemsSort(field: field, direction: descriptor.ascending ? .ascending : .descending))
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  ) -> NSView? {
    guard row < snapshot.rows.count else {
      if tableColumn?.identifier.rawValue == "name" {
        requestNextPageIfNeeded()
        return loadingCell()
      }
      return textCell(identifier: "emptyLoadingCell", text: "", alignment: .left)
    }
    let item = snapshot.rows[row]
    guard let columnIdentifier = tableColumn?.identifier.rawValue else {
      return nil
    }
    switch columnIdentifier {
    case "name":
      return nameCell(for: item)
    case "diskUsed":
      return diskUsedCell(for: item)
    case "statusActions":
      return statusActionsCell(for: item)
    case "path":
      return textCell(
        identifier: "pathCell",
        text: item.location.path(percentEncoded: false),
        alignment: .left
      )
    case "modifiedAt":
      return textCell(
        identifier: "modifiedAtCell",
        text: Self.modifiedAtText(for: item),
        alignment: .left
      )
    case "apparentSize":
      return textCell(
        identifier: "apparentSizeCell",
        text: Self.apparentSizeText(for: item),
        alignment: .left
      )
    default:
      return nil
    }
  }

  private func nameCell(for item: StorageTreeItem) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("nameCell")
    let cell: NSTableCellView
    if let reusedCell = tableView.makeView(withIdentifier: identifier, owner: self)
      as? NSTableCellView
    {
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
        imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
        imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        imageView.widthAnchor.constraint(equalToConstant: 16),
        imageView.heightAnchor.constraint(equalToConstant: 16),
        textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
    }
    cell.imageView?.image = NSImage(
      systemSymbolName: systemImageName(for: item.kind),
      accessibilityDescription: nil
    )
    cell.textField?.stringValue = item.name
    cell.toolTip = item.location.path(percentEncoded: false)
    cell.setAccessibilityLabel(item.name)
    cell.setAccessibilityValue(item.location.path(percentEncoded: false))
    let isRenaming = item.id == snapshot.renamingItemID
    cell.textField?.isEditable = isRenaming
    cell.textField?.isSelectable = isRenaming
    cell.textField?.isBezeled = isRenaming
    cell.textField?.drawsBackground = isRenaming
    cell.textField?.delegate = isRenaming ? self : nil
    cell.textField?.setAccessibilityIdentifier(isRenaming ? "renameField" : nil)
    return cell
  }

  private func diskUsedCell(for item: StorageTreeItem) -> NSTableCellView {
    let text = Self.diskUsedText(for: item)
    let cell = textCell(identifier: "diskUsedCell", text: text, alignment: .center)
    cell.textField?.font = NSFont.monospacedDigitSystemFont(
      ofSize: NSFont.systemFontSize,
      weight: .regular
    )
    cell.setAccessibilityLabel("Disk Used")
    cell.setAccessibilityValue(Self.diskUsedAccessibilityValue(for: item))
    return cell
  }

  private func statusActionsCell(for item: StorageTreeItem) -> NSTableCellView {
    let status = StorageStatusPresentation(item: item)
    let identifier = NSUserInterfaceItemIdentifier("statusActionsCell")
    let cell: NSTableCellView
    let trashButton: TrashActionButton
    if let reusedCell = tableView.makeView(withIdentifier: identifier, owner: self)
      as? NSTableCellView,
      let reusedButton = reusedCell.subviews.compactMap({ $0 as? TrashActionButton }).first
    {
      cell = reusedCell
      trashButton = reusedButton
    } else {
      cell = NSTableCellView()
      cell.identifier = identifier
      let textField = NSTextField(labelWithString: "")
      textField.lineBreakMode = .byTruncatingTail
      textField.translatesAutoresizingMaskIntoConstraints = false
      cell.textField = textField
      cell.addSubview(textField)

      let button = TrashActionButton()
      button.translatesAutoresizingMaskIntoConstraints = false
      button.isBordered = false
      button.imagePosition = .imageOnly
      button.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Move to Trash")
      button.target = self
      button.action = #selector(handleTrashButtonTapped(_:))
      cell.addSubview(button)
      trashButton = button

      NSLayoutConstraint.activate([
        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        textField.trailingAnchor.constraint(
          lessThanOrEqualTo: button.leadingAnchor,
          constant: -6
        ),
        button.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
        button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        button.widthAnchor.constraint(equalToConstant: 20),
        button.heightAnchor.constraint(equalToConstant: 20),
      ])
    }
    cell.textField?.alignment = .left
    cell.textField?.textColor = .secondaryLabelColor
    cell.textField?.stringValue = status.text
    cell.toolTip = status.explanation
    cell.setAccessibilityLabel("Status")
    cell.setAccessibilityValue(status.accessibilityValue)

    let canTrash = snapshot.capabilities[item.id]?.canTrash ?? false
    trashButton.itemID = item.id
    trashButton.isHidden = !canTrash
    trashButton.toolTip = "Move to Trash"
    trashButton.setAccessibilityLabel("Move to Trash")
    return cell
  }

  @objc private func handleTrashButtonTapped(_ sender: TrashActionButton) {
    guard let itemID = sender.itemID else {
      return
    }
    onBeginTrash?(itemID)
  }

  private func textCell(
    identifier identifierText: String,
    text: String,
    alignment: NSTextAlignment
  ) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier(identifierText)
    let cell: NSTableCellView
    if let reusedCell = tableView.makeView(withIdentifier: identifier, owner: self)
      as? NSTableCellView
    {
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
        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
    }
    cell.textField?.alignment = alignment
    cell.textField?.stringValue = text
    return cell
  }

  private static func diskUsedText(for item: StorageTreeItem) -> String {
    guard let diskUsedBytes = item.diskUsedBytes else {
      return "Unavailable"
    }
    let formattedBytes = diskUsedBytes.formatted(.byteCount(style: .file))
    return item.isDiskUsedIncomplete ? "≥ \(formattedBytes)" : formattedBytes
  }

  private static func diskUsedAccessibilityValue(for item: StorageTreeItem) -> String {
    let text = diskUsedText(for: item)
    if item.isDiskUsedIncomplete, item.diskUsedBytes != nil {
      return "Incomplete, at least \(text.dropFirst(2))"
    }
    return text
  }

  private static func apparentSizeText(for item: StorageTreeItem) -> String {
    guard let apparentSizeBytes = item.apparentSizeBytes else {
      return "Unavailable"
    }
    let formattedBytes = apparentSizeBytes.formatted(.byteCount(style: .file))
    return item.isApparentSizeIncomplete ? "≥ \(formattedBytes)" : formattedBytes
  }

  private static func modifiedAtText(for item: StorageTreeItem) -> String {
    guard let modifiedAt = item.modifiedAt else {
      return "Unavailable"
    }
    return modifiedAt.formatted(date: .abbreviated, time: .shortened)
  }

  private func systemImageName(for kind: StorageItemKind) -> String {
    switch kind {
    case .file: "doc"
    case .folder: "folder.fill"
    case .symbolicLink: "arrow.trianglehead.branch"
    case .other: "questionmark.square.dashed"
    case .package: "shippingbox.fill"
    }
  }

  private func loadingCell() -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("loadingCell")
    if let cell = tableView.makeView(withIdentifier: identifier, owner: self)
      as? NSTableCellView
    {
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
      textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
      textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
      textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  private func requestNextPageIfNeeded() {
    guard let nextOffset = snapshot.nextOffset, requestedNextPageOffset != nextOffset else {
      return
    }
    requestedNextPageOffset = nextOffset
    onLoadNextPage?()
  }
}

struct AllItemsTableView: NSViewRepresentable {
  let session: ExplorerSession

  func makeNSView(context: Context) -> AllItemsTableController {
    let controller = AllItemsTableController()
    connect(controller)
    return controller
  }

  func updateNSView(_ controller: AllItemsTableController, context: Context) {
    connect(controller)
    var capabilities: [UUID: ItemCapability] = [:]
    for item in session.allItemsRows {
      capabilities[item.id] = session.capability(for: item)
    }
    controller.apply(
      AllItemsRowsSnapshot(
        rows: session.allItemsRows,
        nextOffset: session.allItemsNextOffset,
        selectedItemIDs: session.selectedItemIDs,
        renamingItemID: session.renamingItemID,
        capabilities: capabilities,
        visibleOptionalColumns: session.visibleOptionalColumns,
        sort: session.allItemsQuery.sort,
        hasActiveQuery: session.allItemsQuery != AllItemsQuery(),
        isLoading: session.isLoadingAllItems
      )
    )
  }

  static func dismantleNSView(_ controller: AllItemsTableController, coordinator: Void) {
    controller.onSelectionChange = nil
    controller.onLoadNextPage = nil
    controller.onBeginRename = nil
    controller.onRenameProposalChange = nil
    controller.onRenameCommit = nil
    controller.onRenameCancel = nil
    controller.onBeginTrash = nil
    controller.onSortChange = nil
    controller.onToggleOptionalColumn = nil
  }

  private func connect(_ controller: AllItemsTableController) {
    controller.onSelectionChange = { [weak session] itemIDs in
      session?.selectItem(itemIDs)
    }
    controller.onLoadNextPage = { [weak session] in
      Task { @MainActor in
        await session?.loadNextAllItemsPage()
      }
    }
    controller.onBeginRename = { [weak session] itemID in
      Task { @MainActor in
        await session?.beginRename(itemID)
      }
    }
    controller.onRenameProposalChange = { [weak session] proposedName in
      session?.updateRenameProposal(proposedName)
    }
    controller.onRenameCommit = { [weak session] in
      Task { @MainActor in
        _ = await session?.commitRename()
      }
    }
    controller.onRenameCancel = { [weak session] in
      session?.cancelRename()
    }
    controller.onBeginTrash = { [weak session] itemID in
      Task { @MainActor in
        await session?.beginTrashConfirmation(itemID)
      }
    }
    controller.onSortChange = { [weak session] sort in
      session?.updateAllItemsSort(sort)
    }
    controller.onToggleOptionalColumn = { [weak session] column in
      session?.toggleAllItemsOptionalColumn(column)
    }
  }
}
