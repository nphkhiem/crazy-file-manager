import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Update Check Outcome Presentation")
struct UpdateCheckOutcomePresentationTests {
  @Test
  func givenNoOutcomeYet_whenResolved_thenPresentationIsNil() {
    #expect(UpdateCheckOutcomePresentation.resolve(nil) == nil)
  }

  @Test
  func givenUpToDate_whenResolved_thenCopyConfirmsNoUpdateIsAvailable() {
    let presentation = UpdateCheckOutcomePresentation.resolve(.upToDate)

    #expect(presentation?.title == "You’re up to date")
  }

  @Test
  func givenAnAvailableUpdate_whenResolved_thenCopyNamesTheNewVersion() {
    let metadata = UpdateMetadata(
      formatVersion: 1,
      version: "2.0.0",
      minimumSystemVersion: "13.0.0",
      downloadURL: URL(string: "https://example.com/CrazyFileManager.dmg")!,
      releaseNotesURL: nil
    )

    let presentation = UpdateCheckOutcomePresentation.resolve(.available(metadata))

    #expect(presentation?.title == "Version 2.0.0 is available")
  }

  @Test
  func givenANetworkFailure_whenResolved_thenCopyStatesTheFailureIsAConnectivityProblem() {
    let presentation = UpdateCheckOutcomePresentation.resolve(.networkFailure("offline"))

    #expect(presentation?.title == "Couldn’t check for updates")
    #expect(presentation?.detail == "offline")
  }

  @Test
  func givenEachRejectionReason_whenResolved_thenItHasDistinctPlainLanguageCopy() {
    let reasons: [UpdateMetadataRejection] = [
      .invalidSignature,
      .malformed,
      .incompatibleFormatVersion,
      .incompatibleSystemVersion,
    ]

    let titles = reasons.compactMap { UpdateCheckOutcomePresentation.resolve(.rejected($0))?.title }

    #expect(titles.count == reasons.count)
    #expect(Set(titles).count == reasons.count)
  }
}
