import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Scan Data Settings Presentation")
struct ScanDataSettingsPresentationTests {
  @Test
  func givenACacheFileSize_whenFormatted_thenItReadsAsAHumanByteCount() throws {
    let completedAt = try #require(date("2026-08-01T10:00:00Z"))
    let expiresAt = try #require(date("2026-08-02T10:00:00Z"))
    let description = ScanScopeDescription(
      selection: .homeFolder,
      availability: .available(ScanScope.homeFolder(URL(filePath: "/Users/debugger")))
    )

    let presentation = ScanDataSettingsPresentation.resolve(
      cacheFileSizeBytes: 2_400_000,
      completedScopeDescription: description,
      completedAt: completedAt,
      expiresAt: expiresAt,
      locale: Locale(identifier: "en_US_POSIX"),
      timeZone: try #require(TimeZone(identifier: "GMT"))
    )

    #expect(presentation.sizeText == "2.4 MB")
    #expect(presentation.scopeText == "Home Folder")
    #expect(presentation.completedText == "Aug 1, 2026 at 10:00 AM")
    #expect(presentation.expiresText == "Aug 2, 2026 at 10:00 AM")
    #expect(presentation.isClearEnabled == true)
  }

  @Test
  func givenNoCachedResults_whenResolved_thenScopeAndTimestampsAreUnavailableAndClearIsDisabled() {
    let presentation = ScanDataSettingsPresentation.resolve(
      cacheFileSizeBytes: nil,
      completedScopeDescription: nil,
      completedAt: nil,
      expiresAt: nil
    )

    #expect(presentation.sizeText == "No saved scan data")
    #expect(presentation.scopeText == nil)
    #expect(presentation.completedText == nil)
    #expect(presentation.expiresText == nil)
    #expect(presentation.isClearEnabled == false)
  }

  private func date(_ iso8601: String) -> Date? {
    ISO8601DateFormatter().date(from: iso8601)
  }
}
