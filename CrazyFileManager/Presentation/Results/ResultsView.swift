import SwiftUI

enum ResultsContentMode: Equatable {
  case largestItems
  case tree
  case allItems
  case unavailable
}

struct ResultsView: View {
  static let inspectorOverlayBreakpoint: CGFloat = 1_000

  static func isInspectorOverlay(forWidth width: CGFloat) -> Bool {
    width < inspectorOverlayBreakpoint
  }

  @Environment(\.colorScheme) private var colorScheme
  @State private var isAllItemsFilterPopoverPresented = false
  @FocusState private var isAllItemsSearchFieldFocused: Bool

  let session: ExplorerSession
  let onChooseCustomScope: () -> Void
  let isInspectorOverlay: Bool
  let isInspectorOverlayPresented: Binding<Bool>

  var body: some View {
    ZStack {
      AmbientBackground()

      VStack(spacing: CFMDesign.Spacing.comfortable) {
        header
        statusCard
        if isInspectorOverlay {
          resultsCanvas
        } else {
          HStack(alignment: .top, spacing: CFMDesign.Spacing.comfortable) {
            resultsCanvas
            FocusedInspectorView(session: session)
          }
        }
      }
      .padding(CFMDesign.Spacing.spacious)
    }
    .sheet(isPresented: isInspectorOverlay ? isInspectorOverlayPresented : .constant(false)) {
      FocusedInspectorView(session: session)
        .padding(CFMDesign.Spacing.spacious)
    }
  }

  private var header: some View {
    HStack(spacing: CFMDesign.Spacing.standard) {
      ZStack {
        RoundedRectangle(
          cornerRadius: CFMDesign.Radius.medium,
          style: .continuous
        )
        .fill(CFMDesign.Color.brand(for: colorScheme).opacity(0.16))

        Image(systemName: "externaldrive.fill")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(CFMDesign.Color.brand(for: colorScheme))
      }
      .frame(width: 46, height: 46)
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text("Crazy File Manager")
          .font(.title3.weight(.semibold))
        Text("Storage overview")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      ScanScopeSelectionView(
        session: session,
        style: .compact,
        onChooseCustomScope: onChooseCustomScope
      )
    }
  }

  private var statusCard: some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.standard) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text(cachePresentation?.title ?? statusTitle)
            .font(.title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
          Text(cachePresentation?.detail ?? statusDetail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("cacheStatusDetail")
            .accessibilityLabel(cachePresentation?.detail ?? statusDetail)
            .accessibilityValue(cachePresentation?.detail ?? statusDetail)
        }

        Spacer()

        progressIndicator
      }

      if let cacheNoticePresentation {
        Divider()
        Label(
          cacheNoticePresentation.title,
          systemImage: "exclamationmark.circle"
        )
        .font(.subheadline.weight(.semibold))
        Text(cacheNoticePresentation.detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("resultsCacheNoticeDetail")
      }

      if let trashSuccessMessage = session.trashSuccessMessage {
        Divider()
        Label(trashSuccessMessage, systemImage: "checkmark.circle")
          .font(.subheadline.weight(.semibold))
          .accessibilityIdentifier("trashSuccessMessage")
      }

      if let clearControl {
        Button(clearControl.title, role: .destructive) {
          Task {
            _ = await session.clearScanData()
          }
        }
        .disabled(!clearControl.isEnabled)
        .accessibilityIdentifier("clearScanDataButton")
      }

      if let currentArea {
        Label {
          Text(currentArea.path(percentEncoded: false))
            .lineLimit(1)
            .truncationMode(.middle)
        } icon: {
          Image(systemName: "folder")
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .help(currentArea.path(percentEncoded: false))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(CFMDesign.Spacing.comfortable)
    .background(.regularMaterial)
    .clipShape(
      RoundedRectangle(
        cornerRadius: CFMDesign.Radius.large,
        style: .continuous
      )
    )
    .overlay(
      RoundedRectangle(
        cornerRadius: CFMDesign.Radius.large,
        style: .continuous
      )
      .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    )
  }

  @ViewBuilder
  private var progressIndicator: some View {
    switch ScanProgressPresentation.resolve(for: session.scanState) {
    case .hidden:
      EmptyView()
    case .indeterminate:
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel("Scan progress")
        .accessibilityValue("Indeterminate")
    case .determinate(let fraction):
      ProgressView(value: fraction)
        .frame(width: 96)
        .accessibilityLabel("Scan progress")
        .accessibilityValue(
          fraction.formatted(
            .percent.precision(.fractionLength(0))
          )
        )
    }
  }

  private var resultsCanvas: some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.standard) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(resultsTitle)
            .font(.headline)
          Text(resultsSubtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Text(resultCountLabel)
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      }

      Divider()

      resultsContent
    }
    .padding(CFMDesign.Spacing.comfortable)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(
      RoundedRectangle(
        cornerRadius: CFMDesign.Radius.large,
        style: .continuous
      )
    )
    .overlay(
      RoundedRectangle(
        cornerRadius: CFMDesign.Radius.large,
        style: .continuous
      )
      .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    )
  }

  @ViewBuilder
  private var resultsContent: some View {
    switch Self.contentMode(
      for: session.scanState,
      treeRoot: session.treeRoot,
      resultsMode: session.resultsMode
    ) {
    case .tree:
      VStack(alignment: .leading, spacing: CFMDesign.Spacing.compact) {
        if let message = session.treeLoadFailureMessage {
          HStack(spacing: CFMDesign.Spacing.compact) {
            Label(message, systemImage: "exclamationmark.circle")
              .foregroundStyle(.secondary)
            Button("Try Again") {
              Task {
                await session.retryFailedTreePages()
              }
            }
            .disabled(!session.loadingTreeItemIDs.isEmpty)
          }
          .font(.caption)
        }
        StorageTreeOutlineView(session: session)
          .accessibilityIdentifier("storageTreeOutline")
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .allItems:
      allItemsContent
    case .largestItems:
      largestItemsContent
    case .unavailable:
      emptyContent
    }
  }

  private var allItemsContent: some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.compact) {
      HStack(spacing: CFMDesign.Spacing.compact) {
        TextField("Search names and paths", text: allItemsSearchTextBinding)
          .textFieldStyle(.roundedBorder)
          .focused($isAllItemsSearchFieldFocused)
          .accessibilityIdentifier("allItemsSearchField")
        Button {
          isAllItemsFilterPopoverPresented.toggle()
        } label: {
          Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
        .popover(isPresented: $isAllItemsFilterPopoverPresented) {
          AllItemsFilterView(
            filters: session.allItemsQuery.filters,
            onChange: { filters in
              session.updateAllItemsFilters(filters)
            }
          )
        }
        .accessibilityIdentifier("allItemsFiltersButton")
      }
      if let message = session.allItemsLoadFailureMessage {
        Label(message, systemImage: "exclamationmark.circle")
          .foregroundStyle(.secondary)
          .font(.caption)
      }
      AllItemsTableView(session: session)
        .accessibilityIdentifier("allItemsTable")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      Button("Focus Search") {
        isAllItemsSearchFieldFocused = true
      }
      .keyboardShortcut("f", modifiers: .command)
      .hidden()
    }
  }

  private var allItemsSearchTextBinding: Binding<String> {
    Binding(
      get: { session.allItemsQuery.searchText },
      set: { session.updateAllItemsSearchText($0) }
    )
  }

  @ViewBuilder
  private var largestItemsContent: some View {
    if session.largestItems.isEmpty {
      emptyContent
    } else {
      Table(session.largestItems, selection: selectionBinding) {
        TableColumn("Name") { item in
          Label(item.name, systemImage: systemImage(for: item.kind))
            .lineLimit(1)
            .help(item.location.path(percentEncoded: false))
        }

        TableColumn("Disk Used") { item in
          Text(diskUsedLabel(for: item))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .width(min: 120, ideal: 150, max: 180)

        TableColumn("Status") { item in
          let status = StorageStatusPresentation(item: item)
          Text(status.text.isEmpty ? "—" : status.text)
            .foregroundStyle(.secondary)
            .help(status.explanation)
            .accessibilityLabel("Status")
            .accessibilityValue(status.accessibilityValue)
        }
        .width(min: 100, ideal: 150, max: 220)
      }
      .accessibilityIdentifier("largestItemsTable")
    }
  }

  private var emptyContent: some View {
    ContentUnavailableView {
      Label(emptyTitle, systemImage: emptySystemImage)
    } description: {
      Text(emptyDetail)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  static func contentMode(
    for scanState: ScanState,
    treeRoot: StorageTreeItem?,
    resultsMode: ResultsMode
  ) -> ResultsContentMode {
    switch scanState {
    case .scanning, .paused, .resuming, .cancelling:
      treeRoot == nil ? .largestItems : (resultsMode == .allItems ? .allItems : .tree)
    case .cancelled, .completed, .failed:
      treeRoot == nil ? .unavailable : (resultsMode == .allItems ? .allItems : .tree)
    case .idle:
      .unavailable
    }
  }

  private var statusTitle: String {
    switch session.scanState {
    case .idle:
      "Ready to scan"
    case .scanning:
      "Scanning accessible items…"
    case .paused:
      "Scan paused"
    case .resuming:
      "Resuming scan…"
    case .cancelling:
      "Cancelling scan…"
    case .cancelled:
      "Scan cancelled"
    case .completed:
      "Scan complete"
    case .failed:
      "Scan stopped"
    }
  }

  private var cachePresentation: ScanCachePresentation? {
    guard
      case .completed = session.scanState,
      let completedScopeDescription = session.completedScopeDescription,
      let completedAt = session.completedAt,
      let expiresAt = session.expiresAt
    else {
      return nil
    }
    return ScanCachePresentation.savedResults(
      scopeTitle: ScanScopePresentation.resolve(completedScopeDescription).title,
      completedAt: completedAt,
      expiresAt: expiresAt
    )
  }

  private var cacheNoticePresentation: ScanCachePresentation? {
    session.cacheNotice.map(ScanCachePresentation.notice)
  }

  private var selectionBinding: Binding<UUID?> {
    Binding(
      get: { session.selectedItemID },
      set: { session.selectItem($0.map { [$0] } ?? []) }
    )
  }

  private var clearControl: ScanCacheClearControl? {
    ScanCachePresentation.clearControl(
      hasCompletedResults: session.completedAt != nil,
      scanState: session.scanState
    )
  }

  private var statusDetail: String {
    switch session.scanState {
    case .idle:
      "Nothing has been scanned."
    case .scanning(let progress),
      .paused(let progress),
      .resuming(let progress),
      .cancelling(let progress):
      countDetail(
        accessibleItemCount: progress.discoveredItemCount,
        issueCount: progress.issueCount
      )
    case .cancelled:
      session.treeRoot == nil
        ? "No partial scan was kept."
        : "The previous completed result is still shown."
    case .completed(let completion):
      countDetail(
        accessibleItemCount: completion.accessibleItemCount,
        issueCount: completion.issueCount
      )
    case .failed(let failure):
      failure.message
    }
  }

  private var currentArea: URL? {
    let progress: ScanProgress
    switch session.scanState {
    case .scanning(let value),
      .paused(let value),
      .resuming(let value),
      .cancelling(let value):
      progress = value
    case .idle, .cancelled, .completed, .failed:
      return nil
    }
    return progress.currentArea
  }

  private var resultCountLabel: String {
    switch Self.contentMode(
      for: session.scanState,
      treeRoot: session.treeRoot,
      resultsMode: session.resultsMode
    ) {
    case .tree:
      let count =
        (session.treeRoot == nil ? 0 : 1)
        + session.treePages.values.reduce(0) {
          $0 + $1.items.count
        }
      return "\(count) \(count == 1 ? "item" : "items") loaded"
    case .allItems:
      let count = session.allItemsRows.count
      return "\(count) \(count == 1 ? "item" : "items") loaded"
    case .largestItems, .unavailable:
      let count = session.largestItems.count
      return "\(count) \(count == 1 ? "item" : "items") shown"
    }
  }

  private var resultsTitle: String {
    switch Self.contentMode(
      for: session.scanState,
      treeRoot: session.treeRoot,
      resultsMode: session.resultsMode
    ) {
    case .tree:
      return "Tree"
    case .allItems:
      return "All Items"
    case .largestItems, .unavailable:
      return "Largest accessible items"
    }
  }

  private var resultsSubtitle: String {
    switch Self.contentMode(
      for: session.scanState,
      treeRoot: session.treeRoot,
      resultsMode: session.resultsMode
    ) {
    case .tree:
      return "Each folder is ordered by Disk Used"
    case .allItems:
      return "Sorted by \(Self.sortFieldLabel(for: session.allItemsQuery.sort.field))"
    case .largestItems, .unavailable:
      return "Ordered by Disk Used"
    }
  }

  private static func sortFieldLabel(for field: AllItemsSortField) -> String {
    switch field {
    case .diskUsed: "Disk Used"
    case .apparentSize: "Apparent Size"
    case .name: "Name"
    case .modifiedAt: "Modified Date"
    case .path: "Path"
    }
  }

  private var emptyTitle: String {
    switch session.scanState {
    case .cancelled, .failed:
      "No partial results kept"
    case .completed:
      "No accessible items found"
    case .idle, .scanning, .paused, .resuming, .cancelling:
      "Looking for accessible items"
    }
  }

  private var emptyDetail: String {
    switch session.scanState {
    case .cancelled, .failed:
      "Start another scan when you are ready."
    case .completed:
      "This scan did not find metadata it could display."
    case .idle, .scanning, .paused, .resuming, .cancelling:
      "Results will appear here as metadata is indexed."
    }
  }

  private var emptySystemImage: String {
    if case .failed = session.scanState {
      return "exclamationmark.circle"
    }
    return "sparkle.magnifyingglass"
  }

  private func countDetail(
    accessibleItemCount: Int,
    issueCount: Int
  ) -> String {
    let accessibleLabel =
      "\(accessibleItemCount) accessible "
      + (accessibleItemCount == 1 ? "item" : "items")
    guard issueCount > 0 else {
      return accessibleLabel
    }
    return "\(accessibleLabel) • \(issueCount) unavailable"
  }

  private func diskUsedLabel(for item: StorageItemSummary) -> String {
    guard let diskUsedBytes = item.diskUsedBytes else {
      return "Unavailable"
    }
    return diskUsedBytes.formatted(.byteCount(style: .file))
  }

  private func systemImage(for kind: StorageItemKind) -> String {
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
}
