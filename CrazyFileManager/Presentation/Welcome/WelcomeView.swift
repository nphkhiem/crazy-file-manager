import SwiftUI

struct WelcomeView: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme

  let session: ExplorerSession
  let onChooseCustomScope: () -> Void
  let onOpenSystemSettings: () -> Void

  var body: some View {
    ZStack {
      AmbientBackground()

      VStack(spacing: CFMDesign.Spacing.spacious) {
        identity
        introduction
        ScanScopeSelectionView(
          session: session,
          style: .full,
          onChooseCustomScope: onChooseCustomScope,
          onOpenSystemSettings: onOpenSystemSettings
        )
        scanAction
        privacyPromise
      }
      .frame(maxWidth: CFMDesign.Layout.welcomeCardWidth)
      .padding(CFMDesign.Spacing.section)
      .background(cardBackground)
      .overlay(cardBorder)
      .shadow(
        color: .black.opacity(colorScheme == .dark ? 0.28 : 0.10),
        radius: 28,
        y: 14
      )
      .padding(CFMDesign.Spacing.section)
    }
  }

  private var identity: some View {
    HStack(spacing: CFMDesign.Spacing.standard) {
      ZStack {
        RoundedRectangle(cornerRadius: CFMDesign.Radius.medium, style: .continuous)
          .fill(CFMDesign.Color.brand(for: colorScheme).opacity(0.16))

        Image(systemName: "externaldrive.fill")
          .font(.system(size: 25, weight: .semibold))
          .foregroundStyle(CFMDesign.Color.brand(for: colorScheme))
      }
      .frame(width: 52, height: 52)
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text("Crazy File Manager")
          .font(.title3.weight(.semibold))
        Text("Private storage insight for your Mac")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
  }

  private var introduction: some View {
    VStack(alignment: .leading, spacing: CFMDesign.Spacing.standard) {
      Text("Find what is using your storage")
        .font(.system(size: 28, weight: .bold))
        .accessibilityAddTraits(.isHeader)

      Text(
        "See the largest accessible files and folders in one calm, honest view. "
          + "Nothing is scanned until you choose to begin."
      )
      .font(.body)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var privacyPromise: some View {
    HStack(spacing: CFMDesign.Spacing.comfortable) {
      promise(icon: "lock.shield.fill", label: "Local only")
      promise(icon: "doc.text.magnifyingglass", label: "Metadata only")
      promise(icon: "hand.raised.fill", label: "You stay in control")
    }
    .frame(maxWidth: .infinity)
    .padding(.top, CFMDesign.Spacing.compact)
  }

  private var scanAction: some View {
    let presentation = ScanScopePresentation.resolve(
      session.scopeDescription
    )
    return Button {
      session.startScan()
    } label: {
      Label(
        presentation.scanButtonTitle,
        systemImage: "sparkle.magnifyingglass"
      )
      .font(.body.weight(.semibold))
      .frame(maxWidth: .infinity)
      .padding(.vertical, CFMDesign.Spacing.compact)
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(
      .roundedRectangle(radius: CFMDesign.Radius.medium)
    )
    .controlSize(.large)
    .tint(CFMDesign.Color.brand(for: colorScheme))
    .disabled(!presentation.isScanEnabled)
    .accessibilityIdentifier("scanButton")
    .accessibilityHint(
      "Starts a local metadata-only scan of the selected scope."
    )
  }

  private var cardBackground: some ShapeStyle {
    if reduceTransparency {
      return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
    }
    return AnyShapeStyle(.regularMaterial)
  }

  private var cardBorder: some View {
    RoundedRectangle(cornerRadius: CFMDesign.Radius.large, style: .continuous)
      .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
  }

  private func promise(icon: String, label: String) -> some View {
    Label(label, systemImage: icon)
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
      .labelStyle(.titleAndIcon)
  }
}
