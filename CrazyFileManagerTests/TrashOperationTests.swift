import Foundation
import Testing

@testable import CrazyFileManager

private struct RecordingTrashExecutor: TrashExecuting {
  let result: Result<Void, any Error>
  func trash(at path: String) throws {
    try result.get()
  }
}

struct TrashOperationTests {
  @Test
  func givenAnEligibleUnchangedTarget_whenTrashPerforms_thenTheExecutorIsInvokedAndSucceeds() throws
  {
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
    let executor = RecordingTrashExecutor(result: .success(()))

    let outcome = TrashOperation.perform(
      expected: target,
      liveEvidenceProvider: provider,
      executor: executor
    )

    #expect(outcome == .trashed)
  }

  @Test
  func
    givenAnEligibleTargetWhoseExecutorFails_whenTrashPerforms_thenItRejectsWithoutClaimingSuccess()
    throws
  {
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
    let executor = RecordingTrashExecutor(
      result: .failure(CocoaError(.featureUnsupported))
    )

    let outcome = TrashOperation.perform(
      expected: target,
      liveEvidenceProvider: provider,
      executor: executor
    )

    guard case .failed(let reason) = outcome else {
      Issue.record("Expected a failed outcome when the executor itself fails")
      return
    }
    #expect(FileManager.default.fileExists(atPath: path))
    #expect(!reason.localizedCaseInsensitiveContains("freed"))
  }

  @Test
  func
    givenATargetDeletedSincePreflightEvidenceWasCaptured_whenTrashPerforms_thenItRejectsWithoutInvokingTheExecutor()
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
    let executor = RecordingTrashExecutor(
      result: .failure(CocoaError(.fileNoSuchFile))
    )

    let outcome = TrashOperation.perform(
      expected: target,
      liveEvidenceProvider: provider,
      executor: executor
    )

    guard case .stale(let reason) = outcome else {
      Issue.record("Expected a stale outcome")
      return
    }
    #expect(!reason.contains(path))
  }

  @Test
  func
    givenATargetThatBecameHardLinkedSincePreflightEvidenceWasCaptured_whenTrashPerforms_thenItRejectsWithoutInvokingTheExecutor()
    throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let provider = FoundationMutationEvidenceProvider()
    let path = fileURL.path(percentEncoded: false)
    let expectedEvidence = try #require(provider.liveEvidence(at: path))
    try FileManager.default.linkItem(
      at: fileURL,
      to: directory.appending(path: "linked.txt")
    )
    let target = ExpectedMutationTarget(
      scanID: ScanID(rawValue: UUID()),
      volumeIdentity: ScanVolumeIdentity(rawValue: "TEST-VOLUME"),
      path: path,
      kind: .file,
      expectedEvidence: expectedEvidence
    )
    let executor = RecordingTrashExecutor(result: .success(()))

    let outcome = TrashOperation.perform(
      expected: target,
      liveEvidenceProvider: provider,
      executor: executor
    )

    guard case .stale = outcome else {
      Issue.record("Expected a stale outcome for a target that became hard-linked")
      return
    }
  }

  @Test
  func
    givenAWritePermissionRevokedSincePreflightEvidenceWasCaptured_whenTrashPerforms_thenItRejectsWithoutInvokingTheExecutor()
    throws
  {
    let directory = try makeTemporaryDirectory()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: directory.path(percentEncoded: false)
      )
      try? FileManager.default.removeItem(at: directory)
    }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let provider = FoundationMutationEvidenceProvider()
    let path = fileURL.path(percentEncoded: false)
    let expectedEvidence = try #require(provider.liveEvidence(at: path))
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: path)
    let target = ExpectedMutationTarget(
      scanID: ScanID(rawValue: UUID()),
      volumeIdentity: ScanVolumeIdentity(rawValue: "TEST-VOLUME"),
      path: path,
      kind: .file,
      expectedEvidence: expectedEvidence
    )
    let executor = RecordingTrashExecutor(result: .success(()))

    let outcome = TrashOperation.perform(
      expected: target,
      liveEvidenceProvider: provider,
      executor: executor
    )

    guard case .stale = outcome else {
      Issue.record("Expected a stale outcome for a write-permission-revoked target")
      return
    }
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
