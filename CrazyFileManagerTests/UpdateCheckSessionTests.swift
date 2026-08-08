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
    let metadata = UpdateCheckSessionTests.metadata(version: "2.0.0")
    let envelopeData = try UpdateCheckSessionTests.envelope(for: metadata, signingKey: signingKey)
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
    let metadata = UpdateCheckSessionTests.metadata(version: "2.0.0")
    let envelopeData = try UpdateCheckSessionTests.envelope(for: metadata, signingKey: signingKey)
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
    let envelopeData = try UpdateCheckSessionTests.envelope(
      for: UpdateCheckSessionTests.metadata(version: "2.0.0"),
      signingKey: signingKey
    )
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

  @Test
  func
    givenTheDownloadedArtifactHashDoesNotMatchTheSignedMetadata_whenConfirmed_thenItFailsAndTheFileIsRemoved()
    async throws
  {
    let signingKey = Curve25519.Signing.PrivateKey()
    let metadata = UpdateCheckSessionTests.metadata(
      version: "2.0.0",
      artifactSHA256Hex: "expected-hash"
    )
    let envelopeData = try UpdateCheckSessionTests.envelope(for: metadata, signingKey: signingKey)
    let downloadedFileURL = FileManager.default.temporaryDirectory
      .appending(path: "\(UUID().uuidString).dmg")
    try Data("not the expected bytes".utf8).write(to: downloadedFileURL)
    defer { try? FileManager.default.removeItem(at: downloadedFileURL) }
    let downloader = ControlledUpdateArtifactDownloading(result: .success(downloadedFileURL))
    let integrityVerifier = ControlledUpdateArtifactIntegrityVerifying(
      result: .success("a-completely-different-hash")
    )
    let fileRevealer = ControlledDownloadedFileRevealing()
    let session = UpdateCheckSessionTests.makeSession(
      updateClient: ControlledUpdateChecking(result: .success(envelopeData)),
      downloader: downloader,
      integrityVerifier: integrityVerifier,
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
    #expect(
      FileManager.default.fileExists(atPath: downloadedFileURL.path(percentEncoded: false)) == false
    )
  }

  @Test
  func
    givenTheIntegrityVerifierThrowsAfterADownloadSucceeds_whenConfirmed_thenTheDownloadedFileIsStillRemoved()
    async throws
  {
    struct HashingError: Error {}
    let signingKey = Curve25519.Signing.PrivateKey()
    let envelopeData = try UpdateCheckSessionTests.envelope(
      for: UpdateCheckSessionTests.metadata(version: "2.0.0"),
      signingKey: signingKey
    )
    let downloadedFileURL = FileManager.default.temporaryDirectory
      .appending(path: "\(UUID().uuidString).dmg")
    try Data("some downloaded bytes".utf8).write(to: downloadedFileURL)
    let downloader = ControlledUpdateArtifactDownloading(result: .success(downloadedFileURL))
    let integrityVerifier = ControlledUpdateArtifactIntegrityVerifying(
      result: .failure(HashingError())
    )
    let session = UpdateCheckSessionTests.makeSession(
      updateClient: ControlledUpdateChecking(result: .success(envelopeData)),
      downloader: downloader,
      integrityVerifier: integrityVerifier,
      preferencesStore: ControlledUpdateCheckPreferencesStoring(isAutomaticCheckEnabled: false),
      publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString()
    )
    await session.checkForUpdatesNow()
    session.beginDownloadConfirmation()

    let didDownload = await session.confirmDownload()

    #expect(didDownload == false)
    #expect(session.downloadFailureMessage != nil)
    #expect(session.downloadedArtifactURL == nil)
    #expect(
      FileManager.default.fileExists(atPath: downloadedFileURL.path(percentEncoded: false)) == false
    )
  }

  @Test
  func
    givenAGenuinelyTamperedDownloadedArtifact_whenConfirmedWithTheRealVerifier_thenItFailsAndIsNeverRevealed()
    async throws
  {
    let signingKey = Curve25519.Signing.PrivateKey()
    let correctBytes = Data("the real, untampered release artifact bytes".utf8)
    let realVerifier = FoundationUpdateArtifactIntegrityVerifier()
    let correctFileURL = FileManager.default.temporaryDirectory
      .appending(path: "\(UUID().uuidString)-correct.dmg")
    try correctBytes.write(to: correctFileURL)
    let expectedHex = try realVerifier.sha256Hex(ofFileAt: correctFileURL)
    try? FileManager.default.removeItem(at: correctFileURL)

    let metadata = UpdateCheckSessionTests.metadata(
      version: "2.0.0",
      artifactSHA256Hex: expectedHex
    )
    let envelopeData = try UpdateCheckSessionTests.envelope(for: metadata, signingKey: signingKey)
    let tamperedFileURL = FileManager.default.temporaryDirectory
      .appending(path: "\(UUID().uuidString)-tampered.dmg")
    try Data("a tampered, substituted set of bytes".utf8).write(to: tamperedFileURL)
    defer { try? FileManager.default.removeItem(at: tamperedFileURL) }
    let downloader = ControlledUpdateArtifactDownloading(result: .success(tamperedFileURL))
    let fileRevealer = ControlledDownloadedFileRevealing()
    let session = UpdateCheckSessionTests.makeSession(
      updateClient: ControlledUpdateChecking(result: .success(envelopeData)),
      downloader: downloader,
      integrityVerifier: realVerifier,
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
    #expect(
      FileManager.default.fileExists(atPath: tamperedFileURL.path(percentEncoded: false)) == false
    )
  }

  @Test
  func
    givenACorrectlyHashedRealDownloadedArtifact_whenConfirmedWithTheRealVerifier_thenItIsRevealed()
    async throws
  {
    let signingKey = Curve25519.Signing.PrivateKey()
    let correctBytes = Data("the real, untampered release artifact bytes".utf8)
    let realVerifier = FoundationUpdateArtifactIntegrityVerifier()
    let downloadedFileURL = FileManager.default.temporaryDirectory
      .appending(path: "\(UUID().uuidString)-correct.dmg")
    try correctBytes.write(to: downloadedFileURL)
    defer { try? FileManager.default.removeItem(at: downloadedFileURL) }
    let expectedHex = try realVerifier.sha256Hex(ofFileAt: downloadedFileURL)

    let metadata = UpdateCheckSessionTests.metadata(
      version: "2.0.0",
      artifactSHA256Hex: expectedHex
    )
    let envelopeData = try UpdateCheckSessionTests.envelope(for: metadata, signingKey: signingKey)
    let downloader = ControlledUpdateArtifactDownloading(result: .success(downloadedFileURL))
    let fileRevealer = ControlledDownloadedFileRevealing()
    let session = UpdateCheckSessionTests.makeSession(
      updateClient: ControlledUpdateChecking(result: .success(envelopeData)),
      downloader: downloader,
      integrityVerifier: realVerifier,
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
  }

  @Test
  func givenAPreviousDownloadFailure_whenARetrySucceeds_thenTheFailureMessageIsCleared()
    async throws
  {
    struct DownloadError: Error {}
    let signingKey = Curve25519.Signing.PrivateKey()
    let envelopeData = try UpdateCheckSessionTests.envelope(
      for: UpdateCheckSessionTests.metadata(version: "2.0.0"),
      signingKey: signingKey
    )
    let downloadedFileURL = URL(filePath: "/tmp/artifact.dmg")
    let downloader = ControlledUpdateArtifactDownloading(result: .failure(DownloadError()))
    let session = UpdateCheckSessionTests.makeSession(
      updateClient: ControlledUpdateChecking(result: .success(envelopeData)),
      downloader: downloader,
      preferencesStore: ControlledUpdateCheckPreferencesStoring(isAutomaticCheckEnabled: false),
      publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString()
    )
    await session.checkForUpdatesNow()
    session.beginDownloadConfirmation()
    _ = await session.confirmDownload()
    #expect(session.downloadFailureMessage != nil)

    downloader.setResult(.success(downloadedFileURL))
    session.beginDownloadConfirmation()
    let didDownload = await session.confirmDownload()

    #expect(didDownload == true)
    #expect(session.downloadFailureMessage == nil)
    #expect(session.downloadedArtifactURL == downloadedFileURL)
  }

  private static func metadata(
    version: String,
    artifactSHA256Hex: String = "expected-hash"
  ) -> UpdateMetadata {
    UpdateMetadata(
      formatVersion: 1,
      version: version,
      minimumSystemVersion: "13.0.0",
      downloadURL: URL(string: "https://example.com/CrazyFileManager.dmg")!,
      releaseNotesURL: nil,
      artifactSHA256Hex: artifactSHA256Hex
    )
  }

  private static func envelope(
    for metadata: UpdateMetadata,
    signingKey: Curve25519.Signing.PrivateKey
  ) throws -> Data {
    let payloadBytes = try JSONEncoder().encode(metadata)
    let signature = try signingKey.signature(for: payloadBytes)
    let envelope: [String: String] = [
      "payload": payloadBytes.base64EncodedString(),
      "signature": signature.base64EncodedString(),
    ]
    return try JSONSerialization.data(withJSONObject: envelope)
  }

  private static func makeSession(
    updateClient: any UpdateChecking = ControlledUpdateChecking(),
    downloader: any UpdateArtifactDownloading = ControlledUpdateArtifactDownloading(
      result: .success(URL(filePath: "/tmp/artifact"))
    ),
    integrityVerifier: any UpdateArtifactIntegrityVerifying =
      ControlledUpdateArtifactIntegrityVerifying(),
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
      integrityVerifier: integrityVerifier,
      preferencesStore: preferencesStore,
      fileRevealer: fileRevealer,
      metadataURL: URL(string: "https://example.com/update-metadata.json")!,
      publicKeyBase64: publicKeyBase64,
      installedVersion: installedVersion,
      currentSystemVersion: currentSystemVersion
    )
  }
}
