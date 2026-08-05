import SwiftUI

struct ScanDataSettingsView: View {
  let session: ExplorerSession
  @State private var cacheFileSizeBytes: Int64?

  private var presentation: ScanDataSettingsPresentation {
    ScanDataSettingsPresentation.resolve(
      cacheFileSizeBytes: cacheFileSizeBytes,
      completedScopeDescription: session.completedScopeDescription,
      completedAt: session.completedAt,
      expiresAt: session.expiresAt
    )
  }

  var body: some View {
    Form {
      LabeledContent("Size") {
        Text(presentation.sizeText)
      }
      .accessibilityIdentifier("scanDataSizeText")

      if let scopeText = presentation.scopeText {
        LabeledContent("Scope") {
          Text(scopeText)
        }
        .accessibilityIdentifier("scanDataScopeText")
      }

      if let completedText = presentation.completedText {
        LabeledContent("Completed") {
          Text(completedText)
        }
        .accessibilityIdentifier("scanDataCompletedText")
      }

      if let expiresText = presentation.expiresText {
        LabeledContent("Expires") {
          Text(expiresText)
        }
        .accessibilityIdentifier("scanDataExpiresText")
      }

      Button("Clear Scan Data", role: .destructive) {
        Task {
          _ = await session.clearScanData()
          cacheFileSizeBytes = await session.cacheFileSizeBytes()
        }
      }
      .disabled(!presentation.isClearEnabled)
      .accessibilityIdentifier("settingsClearScanDataButton")
    }
    .padding(CFMDesign.Spacing.comfortable)
    .task {
      cacheFileSizeBytes = await session.cacheFileSizeBytes()
    }
  }
}
