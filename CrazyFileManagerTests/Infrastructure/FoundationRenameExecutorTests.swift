import Foundation
import Testing

@testable import CrazyFileManager

struct FoundationRenameExecutorTests {
  @Test
  func givenAnExistingFile_whenRenamed_thenTheFileExistsUnderTheNewNameOnly() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let originalURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: originalURL)
    let executor = FoundationRenameExecutor()

    let newPath = try executor.rename(
      at: originalURL.path(percentEncoded: false),
      to: "renamed.txt"
    )

    #expect(newPath == directory.appending(path: "renamed.txt").path(percentEncoded: false))
    #expect(!FileManager.default.fileExists(atPath: originalURL.path(percentEncoded: false)))
    #expect(FileManager.default.fileExists(atPath: newPath))
  }

  @Test
  func givenANonexistentSource_whenRenamed_thenItThrowsWithoutCreatingTheDestination() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let missingURL = directory.appending(path: "does-not-exist.txt")
    let executor = FoundationRenameExecutor()

    #expect(throws: (any Error).self) {
      try executor.rename(
        at: missingURL.path(percentEncoded: false),
        to: "renamed.txt"
      )
    }
    #expect(
      !FileManager.default.fileExists(
        atPath: directory.appending(path: "renamed.txt").path(percentEncoded: false)
      )
    )
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
