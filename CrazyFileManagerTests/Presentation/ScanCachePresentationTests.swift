import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Scan Cache Presentation")
struct ScanCachePresentationTests {
  @Test
  func givenSavedHomeFolderScan_whenPresentationResolves_thenItIdentifiesItsScopeAndCompletion()
    throws
  {
    let completedAt = try #require(date("2026-08-01T10:00:00Z"))
    let expiresAt = try #require(date("2026-08-02T10:00:00Z"))

    let presentation = ScanCachePresentation.savedResults(
      scopeTitle: "Home Folder",
      completedAt: completedAt,
      expiresAt: expiresAt,
      locale: Locale(identifier: "en_US_POSIX"),
      timeZone: try #require(TimeZone(identifier: "GMT"))
    )

    #expect(presentation.title == "Saved scan results")
    #expect(
      presentation.detail
        == "Home Folder was scanned on Aug 1, 2026 at 10:00 AM. Saved results expire on Aug 2, 2026 at 10:00 AM."
    )
    #expect(presentation.scanActionTitle == "Rescan")
    #expect(presentation.clearActionTitle == "Clear Scan Data")
  }

  @Test
  func givenCacheNotices_whenPresentationResolves_thenPathFreeCopyAndActionsRemainHonest() {
    let expectations: [(ScanCacheNotice, ScanCachePresentation)] = [
      (
        .expired,
        ScanCachePresentation(
          title: "Saved scan results expired",
          detail: "Saved scan results have expired. Scan again to refresh them.",
          scanActionTitle: "Scan Again",
          clearActionTitle: nil
        )
      ),
      (
        .cleanupFailed,
        ScanCachePresentation(
          title: "Saved scan data needs attention",
          detail: "Saved scan data couldn’t be removed. Quit and reopen the app.",
          scanActionTitle: "Scan",
          clearActionTitle: nil
        )
      ),
      (
        .reconstructed,
        ScanCachePresentation(
          title: "Saved scan data was rebuilt",
          detail: "Saved scan data was rebuilt after it couldn’t be read.",
          scanActionTitle: "Scan",
          clearActionTitle: nil
        )
      ),
      (
        .refreshFailed,
        ScanCachePresentation(
          title: "Saved scan data needs attention",
          detail: "Saved scan data couldn’t be checked. Try again.",
          scanActionTitle: "Scan",
          clearActionTitle: nil
        )
      ),
    ]

    for (notice, expected) in expectations {
      let presentation = ScanCachePresentation.notice(notice)

      #expect(presentation == expected)
      #expect(!presentation.title.contains("/"))
      #expect(!presentation.detail.contains("/"))
    }
  }

  @Test
  func
    givenCompletedAndActiveScanStates_whenClearControlResolves_thenItOnlyAppearsForStoredResultsAndDisablesDuringActivity()
  {
    let progress = ScanProgress.initial

    #expect(
      ScanCachePresentation.clearControl(
        hasCompletedResults: false,
        scanState: .completed(
          ScanCompletion(accessibleItemCount: 1, issueCount: 0)
        )
      ) == nil
    )
    #expect(
      ScanCachePresentation.clearControl(
        hasCompletedResults: true,
        scanState: .completed(
          ScanCompletion(accessibleItemCount: 1, issueCount: 0)
        )
      ) == ScanCacheClearControl(title: "Clear Scan Data", isEnabled: true)
    )
    #expect(
      ScanCachePresentation.clearControl(
        hasCompletedResults: true,
        scanState: .scanning(progress)
      ) == ScanCacheClearControl(title: "Clear Scan Data", isEnabled: false)
    )
  }

  private func date(_ value: String) -> Date? {
    ISO8601DateFormatter().date(from: value)
  }
}
