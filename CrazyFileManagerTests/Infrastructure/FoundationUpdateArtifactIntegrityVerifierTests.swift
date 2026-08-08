import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Foundation Update Artifact Integrity Verifier")
struct FoundationUpdateArtifactIntegrityVerifierTests {
  @Test
  func givenAnEmptyFile_whenHashed_thenItMatchesThePublishedSHA256TestVector() throws {
    let fileURL = try FoundationUpdateArtifactIntegrityVerifierTests.temporaryFile(
      containing: Data()
    )
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let verifier = FoundationUpdateArtifactIntegrityVerifier()

    let hex = try verifier.sha256Hex(ofFileAt: fileURL)

    #expect(
      hex == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    )
  }

  @Test
  func givenAFileContainingKnownBytes_whenHashed_thenItMatchesThePublishedSHA256TestVector()
    throws
  {
    let fileURL = try FoundationUpdateArtifactIntegrityVerifierTests.temporaryFile(
      containing: Data("abc".utf8)
    )
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let verifier = FoundationUpdateArtifactIntegrityVerifier()

    let hex = try verifier.sha256Hex(ofFileAt: fileURL)

    #expect(
      hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
  }

  @Test
  func givenAMissingFile_whenHashed_thenItThrows() {
    let verifier = FoundationUpdateArtifactIntegrityVerifier()
    let missingURL = URL(filePath: "/tmp/does-not-exist-\(UUID().uuidString).bin")

    #expect(throws: (any Error).self) {
      try verifier.sha256Hex(ofFileAt: missingURL)
    }
  }

  private static func temporaryFile(containing data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "\(UUID().uuidString).bin")
    try data.write(to: url)
    return url
  }
}
