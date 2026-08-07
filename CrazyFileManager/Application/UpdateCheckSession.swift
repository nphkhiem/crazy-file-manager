import Foundation
import Observation

@MainActor
@Observable
final class UpdateCheckSession {
  private(set) var isAutomaticCheckEnabled: Bool
  private(set) var isChecking = false
  private(set) var outcome: UpdateCheckOutcome?
  private(set) var pendingDownloadConfirmation: UpdateMetadata?
  private(set) var downloadedArtifactURL: URL?
  private(set) var downloadFailureMessage: String?

  private let updateClient: any UpdateChecking
  private let downloader: any UpdateArtifactDownloading
  private let integrityVerifier: any UpdateArtifactIntegrityVerifying
  private var preferencesStore: any UpdateCheckPreferencesStoring
  private let fileRevealer: any DownloadedFileRevealing
  private let metadataURL: URL
  private let publicKeyBase64: String
  private let installedVersion: AppVersion
  private let currentSystemVersion: AppVersion
  private var automaticCheckTask: Task<Void, Never>?

  init(
    updateClient: any UpdateChecking,
    downloader: any UpdateArtifactDownloading,
    integrityVerifier: any UpdateArtifactIntegrityVerifying,
    preferencesStore: any UpdateCheckPreferencesStoring,
    fileRevealer: any DownloadedFileRevealing,
    metadataURL: URL,
    publicKeyBase64: String,
    installedVersion: AppVersion,
    currentSystemVersion: AppVersion
  ) {
    self.updateClient = updateClient
    self.downloader = downloader
    self.integrityVerifier = integrityVerifier
    self.preferencesStore = preferencesStore
    self.fileRevealer = fileRevealer
    self.metadataURL = metadataURL
    self.publicKeyBase64 = publicKeyBase64
    self.installedVersion = installedVersion
    self.currentSystemVersion = currentSystemVersion
    isAutomaticCheckEnabled = preferencesStore.isAutomaticCheckEnabled
    if isAutomaticCheckEnabled {
      automaticCheckTask = Task(priority: .utility) { [weak self] in
        await self?.checkForUpdatesNow()
      }
    }
  }

  func waitForAutomaticCheck() async {
    await automaticCheckTask?.value
  }

  func setAutomaticCheckEnabled(_ enabled: Bool) {
    isAutomaticCheckEnabled = enabled
    preferencesStore.isAutomaticCheckEnabled = enabled
  }

  func checkForUpdatesNow() async {
    isChecking = true
    defer { isChecking = false }
    do {
      let envelope = try await updateClient.fetchMetadataEnvelope(from: metadataURL)
      outcome = UpdateMetadataVerifier.verify(
        envelopeData: envelope,
        publicKeyBase64: publicKeyBase64,
        installedVersion: installedVersion,
        currentSystemVersion: currentSystemVersion
      )
    } catch {
      outcome = .networkFailure(error.localizedDescription)
    }
  }

  func beginDownloadConfirmation() {
    guard case .available(let metadata) = outcome else { return }
    pendingDownloadConfirmation = metadata
  }

  func dismissDownloadConfirmation() {
    pendingDownloadConfirmation = nil
  }

  @discardableResult
  func confirmDownload() async -> Bool {
    guard let metadata = pendingDownloadConfirmation else { return false }
    pendingDownloadConfirmation = nil
    downloadFailureMessage = nil
    var downloadedFileURL: URL?
    do {
      let localURL = try await downloader.download(from: metadata.downloadURL)
      downloadedFileURL = localURL
      let actualHex = try integrityVerifier.sha256Hex(ofFileAt: localURL)
      guard actualHex.caseInsensitiveCompare(metadata.artifactSHA256Hex) == .orderedSame else {
        try? FileManager.default.removeItem(at: localURL)
        downloadFailureMessage = "The downloaded file failed an integrity check and was removed."
        return false
      }
      downloadedArtifactURL = localURL
      fileRevealer.reveal(localURL)
      return true
    } catch {
      if let downloadedFileURL {
        try? FileManager.default.removeItem(at: downloadedFileURL)
      }
      downloadFailureMessage = error.localizedDescription
      return false
    }
  }
}
