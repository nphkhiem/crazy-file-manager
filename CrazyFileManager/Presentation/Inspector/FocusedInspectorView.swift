import SwiftUI

struct FocusedInspectorPresentation: Equatable {
  let name: String
  let path: String
  let kindLabel: String
  let diskUsedText: String
  let apparentSizeText: String
  let statusText: String
  let safetyText: String
  let restrictionExplanation: String?
  let emptyStateMessage: String

  static let empty = Self(
    name: "",
    path: "",
    kindLabel: "",
    diskUsedText: "",
    apparentSizeText: "",
    statusText: "",
    safetyText: "",
    restrictionExplanation: nil,
    emptyStateMessage: "Select an item to see its details."
  )

  init(detail: StorageItemDetail, capability: ItemCapability) {
    let item = detail.item
    let status = StorageStatusPresentation(item: item)
    name = item.name
    path = item.location.path(percentEncoded: false)
    kindLabel = Self.kindLabel(for: item.kind)
    diskUsedText = Self.sizeText(item.diskUsedBytes)
    apparentSizeText = Self.sizeText(item.apparentSizeBytes)
    statusText = status.text
    if capability.canRename {
      safetyText = "Normal"
      restrictionExplanation = nil
    } else {
      safetyText = "Restricted"
      restrictionExplanation = capability.cannotRenameReason
    }
    emptyStateMessage = Self.empty.emptyStateMessage
  }

  private init(
    name: String,
    path: String,
    kindLabel: String,
    diskUsedText: String,
    apparentSizeText: String,
    statusText: String,
    safetyText: String,
    restrictionExplanation: String?,
    emptyStateMessage: String
  ) {
    self.name = name
    self.path = path
    self.kindLabel = kindLabel
    self.diskUsedText = diskUsedText
    self.apparentSizeText = apparentSizeText
    self.statusText = statusText
    self.safetyText = safetyText
    self.restrictionExplanation = restrictionExplanation
    self.emptyStateMessage = emptyStateMessage
  }

  private static func kindLabel(for kind: StorageItemKind) -> String {
    switch kind {
    case .file:
      "File"
    case .folder:
      "Folder"
    case .symbolicLink:
      "Symbolic Link"
    case .other:
      "Other"
    case .package:
      "Package"
    }
  }

  private static func sizeText(_ bytes: Int64?) -> String {
    guard let bytes else {
      return "Unavailable"
    }
    return bytes.formatted(.byteCount(style: .file))
  }
}

struct ScanIssueRow: Equatable, Identifiable {
  var id: String { path }
  let path: String
  let message: String
}

struct ScanIssuesPresentation: Equatable {
  struct Group: Equatable, Identifiable {
    var id: String { title }
    let title: String
    let rows: [ScanIssueRow]
  }

  let groups: [Group]
  let emptyStateMessage: String

  static let empty = Self(groups: [], emptyStateMessage: "No scan issues.")

  init(issues: [ScanIssue]) {
    func rows(for kinds: Set<ScanIssue.Kind>) -> [ScanIssueRow] {
      issues.filter { kinds.contains($0.kind) }
        .map { ScanIssueRow(path: $0.location.path(percentEncoded: false), message: $0.message) }
    }
    var groups: [Group] = []
    let inaccessible = rows(for: [.accessDenied])
    if !inaccessible.isEmpty {
      groups.append(Group(title: "Inaccessible (\(inaccessible.count))", rows: inaccessible))
    }
    let incomplete = rows(for: [.metadataUnavailable, .volumeUnavailable])
    if !incomplete.isEmpty {
      groups.append(Group(title: "Incomplete (\(incomplete.count))", rows: incomplete))
    }
    let changed = rows(for: [.changed])
    if !changed.isEmpty {
      groups.append(Group(title: "Changed (\(changed.count))", rows: changed))
    }
    let consistency = rows(for: [.consistency])
    if !consistency.isEmpty {
      groups.append(Group(title: "Consistency (\(consistency.count))", rows: consistency))
    }
    self.groups = groups
    emptyStateMessage = Self.empty.emptyStateMessage
  }

  private init(groups: [Group], emptyStateMessage: String) {
    self.groups = groups
    self.emptyStateMessage = emptyStateMessage
  }
}

struct ActivityRowPresentation: Equatable, Identifiable {
  let id: UUID
  let title: String
  let isFailure: Bool
}

struct SessionActivityPresentation: Equatable {
  let rows: [ActivityRowPresentation]
  let emptyStateMessage: String

  static let empty = Self(rows: [], emptyStateMessage: "No activity yet this session.")

  init(entries: [SessionActivityEntry]) {
    rows = entries.reversed().map { entry in
      let kindLabel = entry.kind == .rename ? "Rename" : "Trash"
      switch entry.outcome {
      case .succeeded:
        return ActivityRowPresentation(
          id: entry.id,
          title: "\(kindLabel): \(entry.itemName)",
          isFailure: false
        )
      case .rejected(let reason):
        return ActivityRowPresentation(
          id: entry.id,
          title: "\(kindLabel) failed: \(entry.itemName) — \(reason)",
          isFailure: true
        )
      }
    }
    emptyStateMessage = Self.empty.emptyStateMessage
  }

  private init(rows: [ActivityRowPresentation], emptyStateMessage: String) {
    self.rows = rows
    self.emptyStateMessage = emptyStateMessage
  }
}

enum InspectorTab: Hashable {
  case inspector
  case issues
  case activity
}

struct FocusedInspectorView: View {
  let session: ExplorerSession
  @State private var renameFieldText: String = ""
  @State private var selectedTab: InspectorTab = .inspector

  private var presentation: FocusedInspectorPresentation {
    guard
      let detail = session.selectedItemDetail,
      let capability = session.selectedItemCapability
    else {
      return .empty
    }
    return FocusedInspectorPresentation(detail: detail, capability: capability)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.standard) {
      Picker("Inspector Tab", selection: $selectedTab) {
        Text("Inspector").tag(InspectorTab.inspector)
        Text("Issues (\(session.issues.count))").tag(InspectorTab.issues)
        Text("Activity").tag(InspectorTab.activity)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityIdentifier("inspectorTabPicker")

      switch selectedTab {
      case .inspector:
        inspectorTabContent
      case .issues:
        issuesTabContent
      case .activity:
        activityTabContent
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(CFMDesign.Spacing.comfortable)
    .frame(width: 260)
    .background(.regularMaterial)
    .clipShape(
      RoundedRectangle(cornerRadius: CFMDesign.Radius.large, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CFMDesign.Radius.large, style: .continuous)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    )
  }

  @ViewBuilder
  private var inspectorTabContent: some View {
    if let completion = session.bulkTrashCompletion {
      bulkCompletionView(completion)
    } else if let preview = session.bulkTrashPreview {
      bulkSelectionSummaryView(preview)
    } else if session.selectedItemDetail == nil {
      Text(presentation.emptyStateMessage)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    } else {
      singleItemDetailView
    }
  }

  private var singleItemDetailView: some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.standard) {
      Text(presentation.name)
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Text(presentation.path)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
      detailRow(label: "Type", value: presentation.kindLabel)
      detailRow(label: "Disk Used", value: presentation.diskUsedText)
      detailRow(label: "Apparent Size", value: presentation.apparentSizeText)
      if !presentation.statusText.isEmpty {
        detailRow(label: "Status", value: presentation.statusText)
      }
      detailRow(label: "Safety", value: presentation.safetyText)
        .accessibilityIdentifier("inspectorSafetyState")
      if let restrictionExplanation = presentation.restrictionExplanation {
        Text(restrictionExplanation)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("inspectorRestrictionExplanation")
      }
      renameControl
    }
  }

  private func bulkSelectionSummaryView(_ preview: BulkTrashConfirmation) -> some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.compact) {
      Text("\(session.selectedItemIDs.count) items selected")
        .font(.headline)
        .accessibilityIdentifier("bulkSelectionSummaryCount")
      Text(combinedDiskUsedText(for: preview))
        .font(.subheadline)
        .foregroundStyle(.secondary)
      if !preview.exclusions.isEmpty {
        Divider()
        bulkProblemSection(title: "Excluded", problems: preview.exclusions)
      }
      Button("Move Selected to Trash") {
        session.beginBulkTrashConfirmation()
      }
      .disabled(preview.eligibleItemIDs.isEmpty)
      .accessibilityIdentifier("moveSelectedToTrashButton")
    }
  }

  private func bulkCompletionView(_ completion: BulkTrashCompletion) -> some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.compact) {
      Text("Bulk Trash complete")
        .font(.headline)
      Text("\(completion.trashedItemIDs.count) moved to Trash")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      if !completion.excluded.isEmpty {
        bulkProblemSection(title: "Excluded", problems: completion.excluded)
      }
      if !completion.stale.isEmpty {
        bulkProblemSection(title: "Stale", problems: completion.stale)
      }
      if !completion.failed.isEmpty {
        bulkProblemSection(title: "Failed", problems: completion.failed)
      }
      Button("Dismiss") {
        session.dismissBulkTrashCompletion()
      }
      .accessibilityIdentifier("dismissBulkTrashCompletionButton")
    }
  }

  private func bulkProblemSection(
    title: String,
    problems: [BulkTrashItemProblem]
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(title) (\(problems.count))")
        .font(.caption.weight(.semibold))
      ForEach(problems, id: \.itemID) { problem in
        Text("\(problem.name): \(problem.reason)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func combinedDiskUsedText(for preview: BulkTrashConfirmation) -> String {
    guard let combinedDiskUsedBytes = preview.combinedDiskUsedBytes else {
      return "Combined Disk Used: Unavailable"
    }
    let formatted = combinedDiskUsedBytes.formatted(.byteCount(style: .file))
    return preview.hasIncompleteDiskUsed
      ? "Combined Disk Used: at least \(formatted)"
      : "Combined Disk Used: \(formatted)"
  }

  @ViewBuilder
  private var issuesTabContent: some View {
    let issuesPresentation = ScanIssuesPresentation(issues: session.issues)
    if issuesPresentation.groups.isEmpty {
      Text(issuesPresentation.emptyStateMessage)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("issuesEmptyState")
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: CFMDesign.Spacing.standard) {
          ForEach(issuesPresentation.groups) { group in
            VStack(alignment: .leading, spacing: 4) {
              Text(group.title)
                .font(.caption.weight(.semibold))
              ForEach(group.rows) { row in
                VStack(alignment: .leading, spacing: 1) {
                  Text(row.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                  Text(row.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.path): \(row.message)")
              }
            }
          }
        }
      }
      .accessibilityIdentifier("issuesTabContent")
    }
  }

  @ViewBuilder
  private var activityTabContent: some View {
    let activityPresentation = SessionActivityPresentation(entries: session.activity)
    if activityPresentation.rows.isEmpty {
      Text(activityPresentation.emptyStateMessage)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("activityEmptyState")
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: CFMDesign.Spacing.compact) {
          ForEach(activityPresentation.rows) { row in
            Text(row.title)
              .font(.caption)
              .foregroundStyle(row.isFailure ? .secondary : .primary)
          }
        }
      }
      .accessibilityIdentifier("activityTabContent")
    }
  }

  @ViewBuilder
  private var renameControl: some View {
    if session.renamingItemID == session.selectedItemID, session.selectedItemID != nil {
      VStack(alignment: .leading, spacing: 4) {
        TextField("Name", text: $renameFieldText)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("inspectorRenameField")
          .onSubmit {
            Task { @MainActor in
              _ = await session.commitRename()
            }
          }
          .onChange(of: renameFieldText) { _, newValue in
            session.updateRenameProposal(newValue)
          }
          .onAppear {
            renameFieldText = session.selectedItemDetail?.item.name ?? ""
          }
        if let message = session.renameValidationMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Button("Cancel") {
          session.cancelRename()
        }
        .buttonStyle(.plain)
        .font(.caption)
      }
    } else if session.selectedItemCapability?.canRename == true,
      let selectedItemID = session.selectedItemID
    {
      Button("Rename") {
        Task { @MainActor in
          await session.beginRename(selectedItemID)
        }
      }
      .accessibilityIdentifier("inspectorRenameButton")
    }
  }

  private func detailRow(label: String, value: String) -> some View {
    HStack {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.caption.weight(.medium))
        .multilineTextAlignment(.trailing)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(label): \(value)")
  }
}
