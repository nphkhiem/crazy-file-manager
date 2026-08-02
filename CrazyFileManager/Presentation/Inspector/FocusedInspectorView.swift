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

  init(detail: StorageItemDetail) {
    let item = detail.item
    let safetyState = RestrictionPolicy.classify(
      path: item.location.path(percentEncoded: false),
      kind: item.kind,
      isRoot: item.isRoot,
      isPackageDescendant: false,
      isShared: item.isShared,
      volume: detail.volumeCharacteristics
    )
    let status = StorageStatusPresentation(item: item)
    name = item.name
    path = item.location.path(percentEncoded: false)
    kindLabel = Self.kindLabel(for: item.kind)
    diskUsedText = Self.sizeText(item.diskUsedBytes)
    apparentSizeText = Self.sizeText(item.apparentSizeBytes)
    statusText = status.text
    switch safetyState {
    case .normal:
      safetyText = "Normal"
      restrictionExplanation = nil
    case .restricted(let reason):
      safetyText = "Restricted"
      restrictionExplanation =
        RestrictionPolicy.capability(for: .restricted(reason))
        .cannotRenameReason
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

struct FocusedInspectorView: View {
  let session: ExplorerSession

  private var presentation: FocusedInspectorPresentation {
    session.selectedItemDetail.map(FocusedInspectorPresentation.init)
      ?? .empty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.standard) {
      if session.selectedItemDetail == nil {
        Text(presentation.emptyStateMessage)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
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
    .accessibilityIdentifier("focusedInspector")
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
  }
}
