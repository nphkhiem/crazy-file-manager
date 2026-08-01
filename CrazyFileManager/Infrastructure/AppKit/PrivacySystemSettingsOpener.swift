import AppKit

@MainActor
struct PrivacySystemSettingsOpener: SystemSettingsOpening {
  static let fullDiskAccessURL = URL(
    string:
      "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
  )!

  func openPrivacySettings() {
    guard !NSWorkspace.shared.open(Self.fullDiskAccessURL) else {
      return
    }
    NSWorkspace.shared.open(
      URL(
        filePath: "/System/Applications/System Settings.app",
        directoryHint: .isDirectory
      ))
  }
}
