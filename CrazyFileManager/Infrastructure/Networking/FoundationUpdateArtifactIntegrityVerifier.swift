import CryptoKit
import Foundation

final class FoundationUpdateArtifactIntegrityVerifier: UpdateArtifactIntegrityVerifying, Sendable {
  private static let chunkSize = 1 << 20

  func sha256Hex(ofFileAt url: URL) throws -> String {
    let fileHandle = try FileHandle(forReadingFrom: url)
    defer { try? fileHandle.close() }

    var hasher = SHA256()
    while true {
      let chunk = try fileHandle.read(upToCount: Self.chunkSize) ?? Data()
      if chunk.isEmpty {
        break
      }
      hasher.update(data: chunk)
    }
    let digest = hasher.finalize()
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
