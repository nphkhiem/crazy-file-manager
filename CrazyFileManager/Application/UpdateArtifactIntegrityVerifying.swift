import Foundation

protocol UpdateArtifactIntegrityVerifying: Sendable {
  func sha256Hex(ofFileAt url: URL) throws -> String
}
