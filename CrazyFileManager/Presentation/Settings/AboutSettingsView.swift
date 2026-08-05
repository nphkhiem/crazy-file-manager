import SwiftUI

struct AboutSettingsView: View {
  private var appName: String {
    Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Crazy File Manager"
  }

  private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "\u{2014}"
  }

  var body: some View {
    VStack(spacing: CFMDesign.Spacing.standard) {
      Text(appName)
        .font(.title2.weight(.semibold))
        .accessibilityIdentifier("aboutAppNameText")

      Text("Version \(appVersion)")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("aboutVersionText")

      Text("A native, local-only storage explorer for macOS.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(CFMDesign.Spacing.comfortable)
  }
}
