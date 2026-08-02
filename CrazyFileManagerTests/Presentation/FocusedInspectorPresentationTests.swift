import Foundation
import Testing

@testable import CrazyFileManager

struct FocusedInspectorPresentationTests {
  @Test
  func givenNormalFileDetail_whenPresented_thenNameKindSizesAndNoRestrictionShow() {
    let detail = StorageItemDetail(
      item: StorageTreeItem(
        id: UUID(),
        parentID: nil,
        location: URL(filePath: "/Users/tester/Documents/report.pdf"),
        name: "report.pdf",
        kind: .file,
        diskUsedBytes: 4_096,
        apparentSizeBytes: 4_000,
        isDiskUsedIncomplete: false,
        isApparentSizeIncomplete: false,
        hasChildren: false,
        isRoot: false
      ),
      volumeCharacteristics: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    let capability = ItemCapability(
      canRename: true,
      cannotRenameReason: nil,
      canTrash: true,
      cannotTrashReason: nil
    )
    let presentation = FocusedInspectorPresentation(detail: detail, capability: capability)

    #expect(presentation.name == "report.pdf")
    #expect(presentation.path == "/Users/tester/Documents/report.pdf")
    #expect(presentation.kindLabel == "File")
    #expect(!presentation.diskUsedText.isEmpty)
    #expect(presentation.safetyText == "Normal")
    #expect(presentation.restrictionExplanation == nil)
  }

  @Test
  func givenRestrictedFolderDetail_whenPresented_thenRestrictionExplanationShows() {
    let detail = StorageItemDetail(
      item: StorageTreeItem(
        id: UUID(),
        parentID: nil,
        location: URL(filePath: "/System/Library/Frameworks/Foundation.framework"),
        name: "Foundation.framework",
        kind: .folder,
        diskUsedBytes: 1_000,
        apparentSizeBytes: 1_000,
        isDiskUsedIncomplete: false,
        isApparentSizeIncomplete: false,
        hasChildren: true,
        isRoot: false
      ),
      volumeCharacteristics: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
    let capability = ItemCapability(
      canRename: false,
      cannotRenameReason: "Protected by the operating system.",
      canTrash: false,
      cannotTrashReason: "Protected by the operating system."
    )
    let presentation = FocusedInspectorPresentation(detail: detail, capability: capability)

    #expect(presentation.safetyText == "Restricted")
    #expect(presentation.restrictionExplanation == "Protected by the operating system.")
  }

  @Test
  func givenNoSelection_whenEmptyPresentationIsResolved_thenItExplainsThereIsNothingSelected() {
    let presentation = FocusedInspectorPresentation.empty
    #expect(presentation.name.isEmpty)
    #expect(presentation.emptyStateMessage == "Select an item to see its details.")
  }
}
