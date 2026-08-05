import CryptoKit
import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Update Check Session")
@MainActor
struct UpdateCheckSessionTests {
  @Test
  func givenAutomaticCheckIsDisabled_whenSessionInitializes_thenNoCheckFires() async throws {
    let updateClient = ControlledUpdateChecking()
    let preferencesStore = ControlledUpdateCheckPreferencesStoring(isAutomaticCheckEnabled: false)
    let session = UpdateCheckSessionTests.makeSession(
      updateClient: updateClient,
      preferencesStore: preferencesStore
    )

    await session.waitForAutomaticCheck()

    #expect(updateClient.fetchCallCount == 0)
  }

  @Test
  func givenAutomaticCheckIsEnabled_whenSessionInitializes_thenACheckFiresOnce() async throws {
    let updateClient = ControlledUpdateChecking()
    let preferencesStore = ControlledUpdateCheckPreferencesStoring(isAutomaticCheckEnabled: true)
    let session = UpdateCheckSessionTests.makeSession(
      updateClient: updateClient,
      preferencesStore: preferencesStore
    )

    await session.waitForAutomaticCheck()

    #expect(updateClient.fetchCallCount == 1)
  }

  @Test
  func givenTheToggleIsChanged_whenSetAutomaticCheckEnabledIsCalled_thenItPersistsViaTheStore()
    async throws
  {
    let preferencesStore = ControlledUpdateCheckPreferencesStoring(isAutomaticCheckEnabled: false)
    let session = UpdateCheckSessionTests.makeSession(
      preferencesStore: preferencesStore
    )

    session.setAutomaticCheckEnabled(true)

    #expect(session.isAutomaticCheckEnabled == true)
    #expect(preferencesStore.isAutomaticCheckEnabled == true)
  }

  @Test
  func givenAutomaticCheckIsDisabled_whenCheckForUpdatesNowIsCalled_thenItStillRuns()
    async throws
  {
    let updateClient = ControlledUpdateChecking()
    let preferencesStore = ControlledUpdateCheckPreferencesStoring(isAutomaticCheckEnabled: false)
    let session = UpdateCheckSessionTests.makeSession(
      updateClient: updateClient,
      preferencesStore: preferencesStore
    )
    await session.waitForAutomaticCheck()

    await session.checkForUpdatesNow()

    #expect(updateClient.fetchCallCount == 1)
  }

  @Test
  func givenTheClientReturnsAValidNewerSignedEnvelope_whenChecked_thenOutcomeIsAvailable()
    async throws
  {
    let signingKey = Curve25519.Signing.PrivateKey()
    let metadata = UpdateMetadata(
      formatVersion: 1,
      version: "2.0.0",
      minimumSystemVersion: "13.0.0",
      downloadURL: URL(string: "https://example.com/CrazyFileManager.dmg")!,
      releaseNotesURL: nil
    )
    let payloadBytes = try JSONEncoder().encode(metadata)
    let signature = try signingKey.signature(for: payloadBytes)
    let envelope: [String: String] = [
      "payload": payloadBytes.base64EncodedString(),
      "signature": signature.base64EncodedString(),
    ]
    let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
    let updateClient = ControlledUpdateChecking(result: .success(envelopeData))
    let session = UpdateCheckSessionTests.makeSession(
      updateClient: updateClient,
      preferencesStore: ControlledUpdateCheckPreferencesStoring(isAutomaticCheckEnabled: false),
      publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString()
    )

    await session.checkForUpdatesNow()

    #expect(session.outcome == .available(metadata))
  }

  @Test
  func givenTheClientThrows_whenChecked_thenOutcomeIsNetworkFailure() async throws {
    struct FetchError: Error {}
    let updateClient = ControlledUpdateChecking(result: .failure(FetchError()))
    let session = UpdateCheckSessionTests.makeSession(
      updateClient: updateClient,
      preferencesStore: ControlledUpdateCheckPreferencesStoring(isAutomaticCheckEnabled: false)
    )

    await session.checkForUpdatesNow()

    guard case .networkFailure = session.outcome else {
      Issue.record("Expected .networkFailure, got \(String(describing: session.outcome))")
      return
    }
  }

  @Test
  func
    givenAnAvailableUpdate_whenDownloadIsConfirmedWithoutBeginningConfirmationFirst_thenNothingHappens()
    async throws
  {
    let downloader = ControlledUpdateArtifactDownloading(
      result: .success(URL(filePath: "/tmp/artifact.dmg"))
    )
    let fileRevealer = ControlledDownloadedFileRevealing()
    let session = UpdateCheckSessionTests.makeSession(
      downloader: downloader,
      preferencesStore: ControlledUpdateCheckPreferencesStoring(isAutomaticCheckEnabled: false),
      fileRevealer: fileRevealer
    )

    let didDownload = await session.confirmDownload()

    #expect(didDownload == false)
    #expect(downloader.downloadCallCount == 0)
    #expect(fileRevealer.revealedURLs.isEmpty)
  }

  @Test
  func givenAConfirmedDownload_whenItSucceeds_thenTheFileIsRevealedAndNotInstalled() async throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let metadata = UpdateMetadata(
      formatVersion: 1,
      version: "2.0.0",
      minimumSystemVersion: "13.0.0",
      downloadURL: URL(string: "https://example.com/CrazyFileManager.dmg")!,
      releaseNotesURL: nil
    )
    let payloadBytes = try JSONEncoder().encode(metadata)
    let signature = try signingKey.signature(for: payloadBytes)
    let envelope: [String: String] = [
      "payload": payloadBytes.base64EncodedString(),
      "signature": signature.base64EncodedString(),
    ]
    let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
    let downloadedFileURL = URL(filePath: "/tmp/artifact.dmg")
    let downloader = ControlledUpdateArtifactDownloading(result: .success(downloadedFileURL))
    let fileRevealer = ControlledDownloadedFileRevealing()
    let session = UpdateCheckSessionTests.makeSession(
      updateClient: ControlledUpdateChecking(result: .success(envelopeData)),
      downloader: downloader,
      preferencesStore: ControlledUpdateCheckPreferencesStoring(isAutomaticCheckEnabled: false),
      fileRevealer: fileRevealer,
      publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString()
    )
    await session.checkForUpdatesNow()
    session.beginDownloadConfirmation()

    let didDownload = await session.confirmDownload()

    #expect(didDownload == true)
    #expect(session.downloadedArtifactURL == downloadedFileURL)
    #expect(fileRevealer.revealedURLs == [downloadedFileURL])
    #expect(session.pendingDownloadConfirmation == nil)
  }

  @Test
  func givenAConfirmedDownload_whenItFails_thenAFailureMessageIsSetAndNothingIsRevealed()
    async throws
  {
    struct DownloadError: Error {}
    let signingKey = Curve25519.Signing.PrivateKey()
    let metadata = UpdateMetadata(
      formatVersion: 1,
      version: "2.0.0",
      minimumSystemVersion: "13.0.0",
      downloadURL: URL(string: "https://example.com/CrazyFileManager.dmg")!,
      releaseNotesURL: nil
    )
    let payloadBytes = try JSONEncoder().encode(metadata)
    let signature = try signingKey.signature(for: payloadBytes)
    let envelope: [String: String] = [
      "payload": payloadBytes.base64EncodedString(),
      "signature": signature.base64EncodedString(),
    ]
    let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
    let downloader = ControlledUpdateArtifactDownloading(result: .failure(DownloadError()))
    let fileRevealer = ControlledDownloadedFileRevealing()
    let session = UpdateCheckSessionTests.makeSession(
      updateClient: ControlledUpdateChecking(result: .success(envelopeData)),
      downloader: downloader,
      preferencesStore: ControlledUpdateCheckPreferencesStoring(isAutomaticCheckEnabled: false),
      fileRevealer: fileRevealer,
      publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString()
    )
    await session.checkForUpdatesNow()
    session.beginDownloadConfirmation()

    let didDownload = await session.confirmDownload()

    #expect(didDownload == false)
    #expect(session.downloadFailureMessage != nil)
    #expect(fileRevealer.revealedURLs.isEmpty)
    #expect(session.downloadedArtifactURL == nil)
  }

  private static func makeSession(
    updateClient: any UpdateChecking = ControlledUpdateChecking(),
    downloader: any UpdateArtifactDownloading = ControlledUpdateArtifactDownloading(
      result: .success(URL(filePath: "/tmp/artifact"))
    ),
    preferencesStore: any UpdateCheckPreferencesStoring =
      ControlledUpdateCheckPreferencesStoring(),
    fileRevealer: any DownloadedFileRevealing = ControlledDownloadedFileRevealing(),
    publicKeyBase64: String = "unused-in-these-tests",
    installedVersion: AppVersion = AppVersion("1.0.0")!,
    currentSystemVersion: AppVersion = AppVersion("14.0.0")!
  ) -> UpdateCheckSession {
    UpdateCheckSession(
      updateClient: updateClient,
      downloader: downloader,
      preferencesStore: preferencesStore,
      fileRevealer: fileRevealer,
      metadataURL: URL(string: "https://example.com/update-metadata.json")!,
      publicKeyBase64: publicKeyBase64,
      installedVersion: installedVersion,
      currentSystemVersion: currentSystemVersion
    )
  }
}
