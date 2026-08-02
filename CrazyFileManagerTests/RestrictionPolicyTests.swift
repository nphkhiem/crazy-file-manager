import Testing

@testable import CrazyFileManager

struct RestrictionPolicyTests {
  @Test
  func givenTreeRootItem_whenClassified_thenStateIsUnsupported() {
    let state = RestrictionPolicy.classify(
      path: "/Users/tester",
      kind: .folder,
      isRoot: true,
      isPackageDescendant: false,
      isShared: false,
      volume: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    #expect(state == .restricted(.unsupported))
  }

  @Test
  func givenOtherKindItem_whenClassified_thenStateIsUnsupported() {
    let state = RestrictionPolicy.classify(
      path: "/Users/tester/socket",
      kind: .other,
      isRoot: false,
      isPackageDescendant: false,
      isShared: false,
      volume: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    #expect(state == .restricted(.unsupported))
  }

  @Test
  func givenSystemFrameworksPath_whenClassified_thenStateIsOperatingSystemProtected() {
    let state = RestrictionPolicy.classify(
      path: "/System/Library/Frameworks/Foundation.framework",
      kind: .folder,
      isRoot: false,
      isPackageDescendant: false,
      isShared: false,
      volume: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    #expect(state == .restricted(.operatingSystemProtected))
  }

  @Test
  func givenApplicationSupportPath_whenClassified_thenStateIsApplicationManaged() {
    let state = RestrictionPolicy.classify(
      path: "/Users/tester/Library/Application Support/SomeApp",
      kind: .folder,
      isRoot: false,
      isPackageDescendant: false,
      isShared: false,
      volume: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    #expect(state == .restricted(.applicationManaged))
  }

  @Test
  func givenNonHomeVolumePathContainingLibraryCachesSegment_whenClassified_thenStateIsNormal() {
    let state = RestrictionPolicy.classify(
      path: "/Volumes/Backup/Projects/Library/Caches/build-artifact",
      kind: .file,
      isRoot: false,
      isPackageDescendant: false,
      isShared: false,
      volume: ScanVolumeCharacteristics(
        isInternal: false,
        isReadOnly: false,
        isRemovable: true
      )
    )
    #expect(state == .normal)
  }

  @Test
  func givenHomeLibraryCachesFolderItself_whenClassified_thenStateIsApplicationManaged() {
    let state = RestrictionPolicy.classify(
      path: "/Users/tester/Library/Caches",
      kind: .folder,
      isRoot: false,
      isPackageDescendant: false,
      isShared: false,
      volume: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    #expect(state == .restricted(.applicationManaged))
  }

  @Test
  func givenVolumesMountRootItself_whenClassified_thenStateIsOperatingSystemProtected() {
    let state = RestrictionPolicy.classify(
      path: "/Volumes",
      kind: .folder,
      isRoot: false,
      isPackageDescendant: false,
      isShared: false,
      volume: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    #expect(state == .restricted(.operatingSystemProtected))
  }

  @Test
  func givenOrdinaryDocumentsPath_whenClassified_thenStateIsNormal() {
    let state = RestrictionPolicy.classify(
      path: "/Users/tester/Documents/report.pdf",
      kind: .file,
      isRoot: false,
      isPackageDescendant: false,
      isShared: false,
      volume: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    #expect(state == .normal)
  }

  @Test
  func givenPackageDescendantItem_whenClassified_thenStateIsPackageInternal() {
    let state = RestrictionPolicy.classify(
      path: "/Users/tester/App.app/Contents/Info.plist",
      kind: .file,
      isRoot: false,
      isPackageDescendant: true,
      isShared: false,
      volume: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    #expect(state == .restricted(.packageInternal))
  }

  @Test
  func givenSharedHardLinkedItem_whenClassified_thenStateIsHighRisk() {
    let state = RestrictionPolicy.classify(
      path: "/Users/tester/Documents/linked.txt",
      kind: .file,
      isRoot: false,
      isPackageDescendant: false,
      isShared: true,
      volume: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    #expect(state == .restricted(.highRisk))
  }

  @Test
  func givenReadOnlyVolumeItem_whenClassified_thenStateIsReadOnlyVolume() {
    let state = RestrictionPolicy.classify(
      path: "/Volumes/Backup/notes.txt",
      kind: .file,
      isRoot: false,
      isPackageDescendant: false,
      isShared: false,
      volume: ScanVolumeCharacteristics(
        isInternal: false,
        isReadOnly: true,
        isRemovable: true
      )
    )
    #expect(state == .restricted(.readOnlyVolume))
  }

  @Test
  func givenSymbolicLinkAtOrdinaryPath_whenClassified_thenStateIsNormal() {
    let state = RestrictionPolicy.classify(
      path: "/Users/tester/Documents/shortcut",
      kind: .symbolicLink,
      isRoot: false,
      isPackageDescendant: false,
      isShared: false,
      volume: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    #expect(state == .normal)
  }

  @Test
  func givenSameVolumeBecomingReadOnly_whenClassified_thenStateReflectsThePermissionChange() {
    let writableVolume = ScanVolumeCharacteristics(
      isInternal: true,
      isReadOnly: false,
      isRemovable: false
    )
    let readOnlyVolume = ScanVolumeCharacteristics(
      isInternal: true,
      isReadOnly: true,
      isRemovable: false
    )
    let path = "/Users/tester/Documents/report.pdf"

    let beforeState = RestrictionPolicy.classify(
      path: path,
      kind: .file,
      isRoot: false,
      isPackageDescendant: false,
      isShared: false,
      volume: writableVolume
    )
    let afterState = RestrictionPolicy.classify(
      path: path,
      kind: .file,
      isRoot: false,
      isPackageDescendant: false,
      isShared: false,
      volume: readOnlyVolume
    )

    #expect(beforeState == .normal)
    #expect(afterState == .restricted(.readOnlyVolume))
  }

  @Test
  func givenCloudOnlyItemAtOrdinaryPath_whenClassified_thenStateIsNormal() {
    let state = RestrictionPolicy.classify(
      path: "/Users/tester/Documents/report.pdf",
      kind: .file,
      isRoot: false,
      isPackageDescendant: false,
      isShared: false,
      volume: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    #expect(state == .normal)
  }

  @Test
  func givenNormalState_whenCapabilityComputed_thenBothActionsAreEligible() {
    let capability = RestrictionPolicy.capability(for: .normal)
    #expect(capability.canRename)
    #expect(capability.cannotRenameReason == nil)
    #expect(capability.canTrash)
    #expect(capability.cannotTrashReason == nil)
  }

  @Test
  func
    givenRestrictedState_whenCapabilityComputed_thenBothActionsAreIneligibleWithAPlainLanguageReason()
  {
    let capability = RestrictionPolicy.capability(for: .restricted(.operatingSystemProtected))
    #expect(!capability.canRename)
    #expect(capability.cannotRenameReason == "Protected by the operating system.")
    #expect(!capability.canTrash)
    #expect(capability.cannotTrashReason == "Protected by the operating system.")
  }

  @Test
  func givenEachRestrictionReason_whenCapabilityComputed_thenReasonTextIsDistinctAndPlainLanguage()
  {
    let expected: [RestrictionReason: String] = [
      .operatingSystemProtected: "Protected by the operating system.",
      .applicationManaged: "Managed by another app.",
      .packageInternal: "Inside a package.",
      .highRisk: "Shared with other locations.",
      .readOnlyVolume: "On a read-only volume.",
      .unsupported: "Not supported.",
    ]
    for (reason, text) in expected {
      let capability = RestrictionPolicy.capability(for: .restricted(reason))
      #expect(capability.cannotRenameReason == text)
    }
  }
}
