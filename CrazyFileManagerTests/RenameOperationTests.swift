import Foundation
import Testing

@testable import CrazyFileManager

private struct RecordingRenameExecutor: RenameExecuting {
  let result: Result<String, any Error>
  func rename(at path: String, to newName: String) throws -> String {
    try result.get()
  }
}

struct RenameOperationTests {
  @Test
  func givenAnEligibleUnchangedTarget_whenRenamePerforms_thenTheExecutorIsInvokedAndSucceeds()
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
    let executor = RecordingRenameExecutor(
      result: .success(directory.appending(path: "renamed.txt").path(percentEncoded: false))
    )

    let outcome = RenameOperation.perform(
      expected: target,
      proposedName: "renamed.txt",
      liveEvidenceProvider: provider,
      executor: executor
    )

    #expect(
      outcome
        == .renamed(newPath: directory.appending(path: "renamed.txt").path(percentEncoded: false))
    )
  }

  @Test
  func
    givenATargetDeletedSincePreflightEvidenceWasCaptured_whenRenamePerforms_thenItRejectsWithoutInvokingTheExecutor()
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
    let executor = RecordingRenameExecutor(
      result: .failure(CocoaError(.fileNoSuchFile))
    )

    let outcome = RenameOperation.perform(
      expected: target,
      proposedName: "renamed.txt",
      liveEvidenceProvider: provider,
      executor: executor
    )

    guard case .rejected(let reason) = outcome else {
      Issue.record("Expected rejection")
      return
    }
    #expect(!reason.contains(path))
  }

  @Test
  func
    givenATargetThatBecameHardLinkedSincePreflightEvidenceWasCaptured_whenRenamePerforms_thenItRejectsWithoutInvokingTheExecutor()
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
    let executor = RecordingRenameExecutor(
      result: .success("should-not-be-reached")
    )

    let outcome = RenameOperation.perform(
      expected: target,
      proposedName: "renamed.txt",
      liveEvidenceProvider: provider,
      executor: executor
    )

    guard case .rejected = outcome else {
      Issue.record("Expected rejection for a target that became hard-linked")
      return
    }
  }

  @Test
  func
    givenATargetReplacedWithADifferentFileAtTheSamePath_whenRenamePerforms_thenItRejectsWithoutInvokingTheExecutor()
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
    try Data("replaced by someone else".utf8).write(to: fileURL)
    let target = ExpectedMutationTarget(
      scanID: ScanID(rawValue: UUID()),
      volumeIdentity: ScanVolumeIdentity(rawValue: "TEST-VOLUME"),
      path: path,
      kind: .file,
      expectedEvidence: expectedEvidence
    )
    let executor = RecordingRenameExecutor(
      result: .success("should-not-be-reached")
    )

    let outcome = RenameOperation.perform(
      expected: target,
      proposedName: "renamed.txt",
      liveEvidenceProvider: provider,
      executor: executor
    )

    #expect(outcome != .renamed(newPath: "should-not-be-reached"))
    guard case .rejected = outcome else {
      Issue.record("Expected rejection for a target replaced with a different file")
      return
    }
  }

  @Test
  func
    givenATargetReplacedWithASymbolicLinkAtTheSamePath_whenRenamePerforms_thenItRejectsWithoutInvokingTheExecutor()
    throws
  {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let linkTargetURL = directory.appending(path: "elsewhere.txt")
    try Data("elsewhere".utf8).write(to: linkTargetURL)
    let provider = FoundationMutationEvidenceProvider()
    let path = fileURL.path(percentEncoded: false)
    let expectedEvidence = try #require(provider.liveEvidence(at: path))
    try FileManager.default.removeItem(at: fileURL)
    try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: linkTargetURL)
    let target = ExpectedMutationTarget(
      scanID: ScanID(rawValue: UUID()),
      volumeIdentity: ScanVolumeIdentity(rawValue: "TEST-VOLUME"),
      path: path,
      kind: .file,
      expectedEvidence: expectedEvidence
    )
    let executor = RecordingRenameExecutor(
      result: .success("should-not-be-reached")
    )

    let outcome = RenameOperation.perform(
      expected: target,
      proposedName: "renamed.txt",
      liveEvidenceProvider: provider,
      executor: executor
    )

    guard case .rejected = outcome else {
      Issue.record("Expected rejection for a target replaced with a symbolic link")
      return
    }
  }

  @Test
  func
    givenTargetPermissionRevokedSincePreflightEvidenceWasCaptured_whenRenamePerforms_thenItRejectsWithoutInvokingTheExecutor()
    throws
  {
    let directory = try makeTemporaryDirectory()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: directory.appending(path: "note.txt").path(percentEncoded: false)
      )
      try? FileManager.default.removeItem(at: directory)
    }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let provider = FoundationMutationEvidenceProvider()
    let path = fileURL.path(percentEncoded: false)
    let expectedEvidence = try #require(provider.liveEvidence(at: path))
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
    let target = ExpectedMutationTarget(
      scanID: ScanID(rawValue: UUID()),
      volumeIdentity: ScanVolumeIdentity(rawValue: "TEST-VOLUME"),
      path: path,
      kind: .file,
      expectedEvidence: expectedEvidence
    )
    let executor = RecordingRenameExecutor(
      result: .success("should-not-be-reached")
    )

    let outcome = RenameOperation.perform(
      expected: target,
      proposedName: "renamed.txt",
      liveEvidenceProvider: provider,
      executor: executor
    )

    guard case .rejected = outcome else {
      Issue.record("Expected rejection for a target with revoked write permission")
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
