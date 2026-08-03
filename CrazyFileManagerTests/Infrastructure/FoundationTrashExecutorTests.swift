import Foundation
import Testing

@testable import CrazyFileManager

struct FoundationTrashExecutorTests {
  @Test
  func givenAnExistingFile_whenTrashed_thenTheSourceNoLongerExistsAtItsOriginalPath() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appending(path: "note.txt")
    try Data("hello".utf8).write(to: fileURL)
    let executor = FoundationTrashExecutor()

    try executor.trash(at: fileURL.path(percentEncoded: false))

    #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
  }

  @Test
  func givenANonexistentSource_whenTrashed_thenItThrows() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let missingURL = directory.appending(path: "does-not-exist.txt")
    let executor = FoundationTrashExecutor()

    #expect(throws: (any Error).self) {
      try executor.trash(at: missingURL.path(percentEncoded: false))
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
