import Foundation
import Testing

@testable import CrazyFileManager

struct MutationPreflightTests {
  @Test
  func givenAnExistingFile_whenLiveEvidenceIsRead_thenDeviceAndInodeAreReturned() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)

    let provider = FoundationMutationEvidenceProvider()
    let evidence = provider.liveEvidence(at: fileURL.path(percentEncoded: false))

    #expect(evidence != nil)
    #expect(evidence?.parentPath == directory.path(percentEncoded: false))
  }

  @Test
  func givenAMissingPath_whenLiveEvidenceIsRead_thenNilIsReturned() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let missingURL = directory.appending(path: "does-not-exist.txt")

    let provider = FoundationMutationEvidenceProvider()
    let evidence = provider.liveEvidence(at: missingURL.path(percentEncoded: false))

    #expect(evidence == nil)
  }

  @Test
  func givenUnchangedFile_whenValidated_thenPreflightAccepts() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let provider = FoundationMutationEvidenceProvider()
    let path = fileURL.path(percentEncoded: false)
    let expectedEvidence = try #require(provider.liveEvidence(at: path))
    let target = ExpectedMutationTarget(
      scanID: ScanID(rawValue: UUID()),
      volumeIdentity: ScanVolumeIdentity(rawValue: "TEST-VOLUME"),
      path: path,
      kind: .file,
      expectedEvidence: expectedEvidence
    )

    let result = MutationPreflight.validate(expected: target, liveEvidenceProvider: provider)

    #expect(result == .accepted)
  }

  @Test
  func
    givenFileDeletedSinceExpectedEvidenceWasCaptured_whenValidated_thenPreflightRejectsAsMissing()
    throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let provider = FoundationMutationEvidenceProvider()
    let path = fileURL.path(percentEncoded: false)
    let expectedEvidence = try #require(provider.liveEvidence(at: path))
    try FileManager.default.removeItem(at: fileURL)
    let target = ExpectedMutationTarget(
      scanID: ScanID(rawValue: UUID()),
      volumeIdentity: ScanVolumeIdentity(rawValue: "TEST-VOLUME"),
      path: path,
      kind: .file,
      expectedEvidence: expectedEvidence
    )

    let result = MutationPreflight.validate(expected: target, liveEvidenceProvider: provider)

    guard case .rejected(let reason) = result else {
      Issue.record("Expected rejection")
      return
    }
    #expect(!reason.contains(path))
  }

  @Test
  func givenFileReplacedWithADifferentFileAtTheSamePath_whenValidated_thenPreflightRejects() throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let provider = FoundationMutationEvidenceProvider()
    let path = fileURL.path(percentEncoded: false)
    let expectedEvidence = try #require(provider.liveEvidence(at: path))
    try FileManager.default.removeItem(at: fileURL)
    try Data("replaced".utf8).write(to: fileURL)
    let target = ExpectedMutationTarget(
      scanID: ScanID(rawValue: UUID()),
      volumeIdentity: ScanVolumeIdentity(rawValue: "TEST-VOLUME"),
      path: path,
      kind: .file,
      expectedEvidence: expectedEvidence
    )

    let result = MutationPreflight.validate(expected: target, liveEvidenceProvider: provider)

    #expect(result != .accepted)
  }

  @Test
  func givenFileMovedToADifferentParent_whenValidated_thenPreflightRejects() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let originalURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: originalURL)
    let provider = FoundationMutationEvidenceProvider()
    let path = originalURL.path(percentEncoded: false)
    let expectedEvidence = try #require(provider.liveEvidence(at: path))
    let nestedDirectory = directory.appending(path: "nested", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    let movedURL = nestedDirectory.appending(path: "note.txt")
    try FileManager.default.moveItem(at: originalURL, to: movedURL)
    let target = ExpectedMutationTarget(
      scanID: ScanID(rawValue: UUID()),
      volumeIdentity: ScanVolumeIdentity(rawValue: "TEST-VOLUME"),
      path: path,
      kind: .file,
      expectedEvidence: expectedEvidence
    )

    let result = MutationPreflight.validate(expected: target, liveEvidenceProvider: provider)

    #expect(result != .accepted)
  }

  @Test
  func givenRejection_whenValidated_thenNoMutationRecorderIsEverInvoked() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let provider = FoundationMutationEvidenceProvider()
    let path = fileURL.path(percentEncoded: false)
    let expectedEvidence = try #require(provider.liveEvidence(at: path))
    try FileManager.default.removeItem(at: fileURL)
    let target = ExpectedMutationTarget(
      scanID: ScanID(rawValue: UUID()),
      volumeIdentity: ScanVolumeIdentity(rawValue: "TEST-VOLUME"),
      path: path,
      kind: .file,
      expectedEvidence: expectedEvidence
    )
    var mutationWasInvoked = false

    let result = MutationPreflight.validate(expected: target, liveEvidenceProvider: provider)
    if result == .accepted {
      mutationWasInvoked = true
    }

    #expect(!mutationWasInvoked)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }
}
