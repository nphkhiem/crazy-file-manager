import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Scan Scope Presentation")
struct ScanScopePresentationTests {
  @Test
  func givenScopeStates_whenPresentationResolves_thenCopyAndActionsRemainHonest() {
    let home = scope(
      kind: .homeFolder,
      location: "/Users/tester",
      isReadOnly: false,
      isRemovable: false
    )
    let internalDisk = scope(
      kind: .entireInternalDisk,
      location: "/",
      isReadOnly: false,
      isRemovable: false
    )
    let readOnly = scope(
      kind: .custom,
      location: "/Volumes/Archive",
      isReadOnly: true,
      isRemovable: false
    )
    let removable = scope(
      kind: .custom,
      location: "/Volumes/Portable",
      isReadOnly: false,
      isRemovable: true
    )
    let customReadOnly = CustomScopeReference(
      displayName: "Archive",
      lastKnownLocation: readOnly.location
    )
    let customRemovable = CustomScopeReference(
      displayName: "Portable",
      lastKnownLocation: removable.location
    )
    let expectations: [(ScanScopeDescription, ScanScopePresentation)] = [
      (
        ScanScopeDescription(
          selection: .homeFolder,
          availability: .available(home)
        ),
        ScanScopePresentation(
          title: "Home Folder",
          location: "/Users/tester",
          statusText: "Recommended for a fast, private overview.",
          systemImage: "house.fill",
          isRecommended: true,
          isScanEnabled: true,
          showsChooseAgain: false,
          scanButtonTitle: "Scan Home Folder"
        )
      ),
      (
        ScanScopeDescription(
          selection: .entireInternalDisk,
          availability: .available(internalDisk)
        ),
        ScanScopePresentation(
          title: "Entire Internal Disk",
          location: "/",
          statusText: "Scans the startup disk. Some locations may remain unavailable.",
          systemImage: "internaldrive.fill",
          isRecommended: false,
          isScanEnabled: true,
          showsChooseAgain: false,
          scanButtonTitle: "Scan Entire Internal Disk"
        )
      ),
      (
        ScanScopeDescription(
          selection: .custom(customReadOnly),
          availability: .available(readOnly)
        ),
        ScanScopePresentation(
          title: "Archive",
          location: "/Volumes/Archive",
          statusText: "Read-only location. Scanning does not modify it.",
          systemImage: "externaldrive.fill",
          isRecommended: false,
          isScanEnabled: true,
          showsChooseAgain: true,
          scanButtonTitle: "Scan Archive"
        )
      ),
      (
        ScanScopeDescription(
          selection: .custom(customRemovable),
          availability: .available(removable)
        ),
        ScanScopePresentation(
          title: "Portable",
          location: "/Volumes/Portable",
          statusText: "Removable volume. Keep it connected while scanning.",
          systemImage: "externaldrive.fill",
          isRecommended: false,
          isScanEnabled: true,
          showsChooseAgain: true,
          scanButtonTitle: "Scan Portable"
        )
      ),
      (
        ScanScopeDescription(
          selection: .custom(customReadOnly),
          availability: .unsupported(location: readOnly.location)
        ),
        ScanScopePresentation(
          title: "Archive",
          location: "/Volumes/Archive",
          statusText:
            "This volume does not provide the stable identity required for safe scanning.",
          systemImage: "externaldrive.badge.exclamationmark",
          isRecommended: false,
          isScanEnabled: false,
          showsChooseAgain: true,
          scanButtonTitle: "Scan Archive"
        )
      ),
      (
        ScanScopeDescription(
          selection: .custom(customRemovable),
          availability: .disconnected(lastKnownLocation: removable.location)
        ),
        ScanScopePresentation(
          title: "Portable",
          location: "/Volumes/Portable",
          statusText: "This location is disconnected or no longer available.",
          systemImage: "externaldrive.badge.exclamationmark",
          isRecommended: false,
          isScanEnabled: false,
          showsChooseAgain: true,
          scanButtonTitle: "Scan Portable"
        )
      ),
    ]

    for (description, expected) in expectations {
      #expect(ScanScopePresentation.resolve(description) == expected)
    }
  }

  @Test
  func givenScopeChoices_whenGuidanceResolves_thenOnlyInternalDiskExplainsFullDiskAccess() {
    let expected = ScanScopePermissionGuidance(
      message:
        "macOS may restrict parts of the startup disk. Full Disk Access can improve coverage, but Crazy File Manager cannot detect, grant, or bypass that permission.",
      openSettingsTitle: "Open System Settings",
      dismissTitle: "Not Now"
    )

    #expect(
      ScanScopePermissionGuidance.resolve(.entireInternalDisk)
        == expected
    )
    #expect(ScanScopePermissionGuidance.resolve(.homeFolder) == nil)
    #expect(
      ScanScopePermissionGuidance.resolve(
        .custom(
          CustomScopeReference(
            displayName: "Archive",
            lastKnownLocation: URL(filePath: "/Volumes/Archive")
          )
        )) == nil
    )
  }

  @Test
  @MainActor
  func givenFullDiskAccessGuidance_whenSettingsDestinationResolves_thenPrivacyPaneIsTargeted() {
    #expect(
      PrivacySystemSettingsOpener.fullDiskAccessURL.absoluteString
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )
  }

  private func scope(
    kind: ScanScope.Kind,
    location: String,
    isReadOnly: Bool,
    isRemovable: Bool
  ) -> ScanScope {
    ScanScope(
      kind: kind,
      location: URL(filePath: location, directoryHint: .isDirectory),
      volumeIdentity: ScanVolumeIdentity(rawValue: "VOLUME-\(location)"),
      volumeCharacteristics: ScanVolumeCharacteristics(
        isInternal: kind != .custom,
        isReadOnly: isReadOnly,
        isRemovable: isRemovable
      )
    )
  }
}
