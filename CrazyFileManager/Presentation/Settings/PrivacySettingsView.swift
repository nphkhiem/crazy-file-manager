import SwiftUI

struct PrivacySettingsView: View {
  var body: some View {
    Form {
      Text(
        "Crazy File Manager scans and searches your files entirely on this Mac. "
          + "It reads only file and folder metadata such as names, sizes, and dates "
          + "\u{2014} never file contents."
      )
      .accessibilityIdentifier("privacyMetadataOnlyText")

      Text(
        "There is no account, no advertising, no analytics, no behavioral telemetry, "
          + "and no automatic crash upload."
      )
      .accessibilityIdentifier("privacyNoTelemetryText")

      Text("Session Activity is kept in memory only and clears when you quit the app.")
        .accessibilityIdentifier("privacySessionActivityText")

      Text(
        "At most one completed scan is retained on disk, and it expires automatically "
          + "24 hours after it completes."
      )
      .accessibilityIdentifier("privacyRetentionText")

      Text(
        "Update Checks is off by default. When enabled, or when you check manually, "
          + "the app sends a single unauthenticated network request to a fixed metadata "
          + "address \u{2014} no file names, paths, or scan data are ever included."
      )
      .accessibilityIdentifier("privacyUpdateCheckText")
    }
    .padding(CFMDesign.Spacing.comfortable)
  }
}
