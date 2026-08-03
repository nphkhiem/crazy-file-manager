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

  @Test
  func givenNoIssues_whenScanIssuesPresentationIsResolved_thenGroupsAreEmpty() {
    let presentation = ScanIssuesPresentation(issues: [])
    #expect(presentation.groups.isEmpty)
    #expect(!presentation.emptyStateMessage.isEmpty)
  }

  @Test
  func givenOneIssueOfEachKind_whenScanIssuesPresentationIsResolved_thenFourGroupsAppear() {
    let accessDenied = ScanIssue(
      location: URL(filePath: "/Users/tester/locked"),
      kind: .accessDenied,
      message: "The item could not be accessed."
    )
    let metadataUnavailable = ScanIssue(
      location: URL(filePath: "/Users/tester/nometadata"),
      kind: .metadataUnavailable,
      message: "The item metadata could not be read."
    )
    let volumeUnavailable = ScanIssue(
      location: URL(filePath: "/Users/tester/othervolume"),
      kind: .volumeUnavailable,
      message: "The item is on a different or unavailable volume."
    )
    let changed = ScanIssue(
      location: URL(filePath: "/Users/tester/vanished"),
      kind: .changed,
      message: "This item changed while it was being scanned."
    )
    let consistency = ScanIssue(
      location: URL(filePath: "/Users/tester/ambiguous"),
      kind: .consistency,
      message: "This item’s filesystem identity could not be confirmed."
    )
    let presentation = ScanIssuesPresentation(
      issues: [accessDenied, metadataUnavailable, volumeUnavailable, changed, consistency]
    )

    #expect(presentation.groups.count == 4)
    #expect(presentation.groups[0].title.hasPrefix("Inaccessible"))
    #expect(presentation.groups[0].rows.map(\.path) == ["/Users/tester/locked"])
    #expect(presentation.groups[1].title.hasPrefix("Incomplete"))
    #expect(
      Set(presentation.groups[1].rows.map(\.path))
        == ["/Users/tester/nometadata", "/Users/tester/othervolume"]
    )
    #expect(presentation.groups[2].title.hasPrefix("Changed"))
    #expect(presentation.groups[2].rows.map(\.path) == ["/Users/tester/vanished"])
    #expect(presentation.groups[3].title.hasPrefix("Consistency"))
    #expect(presentation.groups[3].rows.map(\.path) == ["/Users/tester/ambiguous"])
    #expect(presentation.groups[3].rows.first?.message == consistency.message)
  }

  @Test
  func givenNoActivity_whenSessionActivityPresentationIsResolved_thenRowsAreEmpty() {
    let presentation = SessionActivityPresentation(entries: [])
    #expect(presentation.rows.isEmpty)
    #expect(!presentation.emptyStateMessage.isEmpty)
  }

  @Test
  func givenSucceededAndRejectedEntries_whenActivityPresentationIsResolved_thenRowsAreReversed() {
    let first = SessionActivityEntry(
      id: UUID(),
      kind: .rename,
      itemName: "first.bin",
      outcome: .succeeded,
      occurredAt: Date(timeIntervalSince1970: 0)
    )
    let second = SessionActivityEntry(
      id: UUID(),
      kind: .trash,
      itemName: "second.bin",
      outcome: .rejected(reason: "This item can no longer be found."),
      occurredAt: Date(timeIntervalSince1970: 1)
    )
    let presentation = SessionActivityPresentation(entries: [first, second])

    #expect(presentation.rows.count == 2)
    #expect(presentation.rows[0].title.contains("second.bin"))
    #expect(presentation.rows[0].isFailure)
    #expect(presentation.rows[1].title.contains("first.bin"))
    #expect(!presentation.rows[1].isFailure)
  }
}
