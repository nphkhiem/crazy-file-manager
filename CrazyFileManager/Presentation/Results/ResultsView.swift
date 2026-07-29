import SwiftUI

struct ResultsView: View {
  @Environment(\.colorScheme) private var colorScheme

  let session: ExplorerSession

  var body: some View {
    ZStack {
      AmbientBackground()

      VStack(spacing: CFMDesign.Spacing.comfortable) {
        header
        statusCard
        resultsCanvas
      }
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
        Text("Home Folder")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Label(
        session.selectedScope.location.lastPathComponent,
        systemImage: "house.fill"
      )
      .font(.callout.weight(.medium))
      .lineLimit(1)
      .help(session.selectedScope.location.path(percentEncoded: false))
    }
  }

  private var statusCard: some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.standard) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text(statusTitle)
            .font(.title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
          Text(statusDetail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if case .scanning = session.scanState {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Scanning")
        }
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

  private var resultsCanvas: some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.standard) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Largest accessible items")
            .font(.headline)
          Text("Ordered by Disk Used")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Text(resultCountLabel)
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      }

      Divider()

      if session.largestItems.isEmpty {
        ContentUnavailableView {
          Label(emptyTitle, systemImage: emptySystemImage)
        } description: {
          Text(emptyDetail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Table(session.largestItems) {
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
        }
        .accessibilityIdentifier("largestItemsTable")
      }
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

  private var statusTitle: String {
    switch session.scanState {
    case .idle:
      "Ready to scan"
    case .scanning:
      "Scanning accessible items…"
    case .completed:
      "Scan complete"
    case .failed:
      "Scan stopped"
    }
  }

  private var statusDetail: String {
    switch session.scanState {
    case .idle:
      "Nothing has been scanned."
    case .scanning(let progress):
      countDetail(
        accessibleItemCount: progress.discoveredItemCount,
        issueCount: progress.issueCount
      )
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
    guard case .scanning(let progress) = session.scanState else {
      return nil
    }
    return progress.currentArea
  }

  private var resultCountLabel: String {
    let count = session.largestItems.count
    return "\(count) \(count == 1 ? "item" : "items") shown"
  }

  private var emptyTitle: String {
    switch session.scanState {
    case .failed:
      "No partial results kept"
    case .completed:
      "No accessible items found"
    case .idle, .scanning:
      "Looking for accessible items"
    }
  }

  private var emptyDetail: String {
    switch session.scanState {
    case .failed:
      "Start another scan when you are ready."
    case .completed:
      "This scan did not find metadata it could display."
    case .idle, .scanning:
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
    }
  }
}
