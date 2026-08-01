import SwiftUI

struct ScanScopeSelectionView: View {
  enum Style {
    case full
    case compact
  }

  @Environment(\.colorScheme) private var colorScheme

  let session: ExplorerSession
  let style: Style
  let onChooseCustomScope: () -> Void
  var onOpenSystemSettings: (() -> Void)?

  var body: some View {
    switch style {
    case .full:
      fullSelection
    case .compact:
      compactSelection
    }
  }

  private var presentation: ScanScopePresentation {
    ScanScopePresentation.resolve(session.scopeDescription)
  }

  private var fullSelection: some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.standard) {
      HStack {
        Text("SCAN SCOPE")
          .font(.caption.weight(.semibold))
          .tracking(0.7)
          .foregroundStyle(.secondary)

        Spacer()

        if presentation.isRecommended {
          Text("RECOMMENDED")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CFMDesign.Color.brand(for: colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
              CFMDesign.Color.brand(for: colorScheme).opacity(0.13),
              in: Capsule()
            )
        }
      }

      scopeChoices
      selectedScopeCard

      if let guidance = ScanScopePermissionGuidance.resolve(
        session.scopeSelection
      ), !session.isFullDiskAccessGuidanceDismissed {
        permissionGuidance(guidance)
      }
    }
    .padding(CFMDesign.Spacing.comfortable)
    .background(
      Color(nsColor: .controlBackgroundColor).opacity(
        colorScheme == .dark ? 0.72 : 0.86
      ),
      in: RoundedRectangle(
        cornerRadius: CFMDesign.Radius.medium,
        style: .continuous
      )
    )
    .overlay(
      RoundedRectangle(
        cornerRadius: CFMDesign.Radius.medium,
        style: .continuous
      )
      .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Selected scan scope")
  }

  private var scopeChoices: some View {
    HStack(spacing: CFMDesign.Spacing.compact) {
      scopeButton(
        "Home Folder",
        systemImage: "house.fill",
        identifier: "homeFolderScopeButton",
        isSelected: session.scopeSelection == .homeFolder
      ) {
        session.selectHomeFolder()
      }
      scopeButton(
        "Entire Internal Disk",
        systemImage: "internaldrive.fill",
        identifier: "entireDiskScopeButton",
        isSelected: session.scopeSelection == .entireInternalDisk
      ) {
        session.selectEntireInternalDisk()
      }
      scopeButton(
        "Choose Folder or Volume",
        systemImage: "folder.badge.plus",
        identifier: "customScopeButton",
        isSelected: {
          if case .custom = session.scopeSelection {
            return true
          }
          return false
        }()
      ) {
        onChooseCustomScope()
      }
    }
    .disabled(!session.canChangeScope)
  }

  private var selectedScopeCard: some View {
    HStack(spacing: CFMDesign.Spacing.standard) {
      Image(systemName: presentation.systemImage)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(CFMDesign.Color.brand(for: colorScheme))
        .frame(width: 36, height: 36)
        .background(
          CFMDesign.Color.brand(for: colorScheme).opacity(0.12),
          in: RoundedRectangle(
            cornerRadius: CFMDesign.Radius.small,
            style: .continuous
          )
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(presentation.title)
          .font(.body.weight(.semibold))
        Text(presentation.location)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(presentation.location)
        Text(presentation.statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()

      if presentation.showsChooseAgain {
        Button("Choose Again", action: onChooseCustomScope)
          .disabled(!session.canChangeScope)
          .accessibilityIdentifier("chooseCustomScopeAgainButton")
      } else {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(CFMDesign.Color.brand(for: colorScheme))
          .accessibilityLabel("Selected")
      }
    }
  }

  private var compactSelection: some View {
    VStack(alignment: .trailing, spacing: 2) {
      Menu {
        Button("Home Folder") {
          session.selectHomeFolder()
        }
        Button("Entire Internal Disk") {
          session.selectEntireInternalDisk()
        }
        Button("Choose Folder or Volume", action: onChooseCustomScope)
      } label: {
        Label(presentation.title, systemImage: presentation.systemImage)
      }
      .disabled(!session.canChangeScope)
      .accessibilityIdentifier("resultsScopeMenu")

      Text(presentation.location)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .help(presentation.location)

      Text(presentation.statusText)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: 360, alignment: .trailing)
  }

  private func permissionGuidance(
    _ guidance: ScanScopePermissionGuidance
  ) -> some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.compact) {
      Label("Full Disk Access is optional", systemImage: "lock.shield")
        .font(.callout.weight(.semibold))
      Text(guidance.message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Button(guidance.openSettingsTitle) {
          onOpenSystemSettings?()
        }
        Button(guidance.dismissTitle) {
          session.dismissFullDiskAccessGuidance()
        }
      }
      .controlSize(.small)
    }
    .padding(CFMDesign.Spacing.standard)
    .background(
      CFMDesign.Color.brand(for: colorScheme).opacity(0.08),
      in: RoundedRectangle(
        cornerRadius: CFMDesign.Radius.small,
        style: .continuous
      )
    )
    .accessibilityIdentifier("fullDiskAccessGuidance")
  }

  private func scopeButton(
    _ title: String,
    systemImage: String,
    identifier: String,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .tint(
      isSelected
        ? CFMDesign.Color.brand(for: colorScheme)
        : nil
    )
    .accessibilityIdentifier(identifier)
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
  }
}
