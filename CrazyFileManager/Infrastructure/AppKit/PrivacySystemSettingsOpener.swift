import AppKit

@MainActor
struct PrivacySystemSettingsOpener: SystemSettingsOpening {
  func openPrivacySettings() {
    NSWorkspace.shared.open(
      URL(
        filePath: "/System/Applications/System Settings.app",
        directoryHint: .isDirectory
      )
    )
  }
}
