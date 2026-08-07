import CryptoKit
import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Update Metadata Verifier")
struct UpdateMetadataVerifierTests {
  @Test
  func givenAValidlySignedNewerVersion_whenVerified_thenItIsAvailable() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let metadata = UpdateMetadataVerifierTests.metadata(version: "2.0.0")
    let envelope = try UpdateMetadataVerifierTests.envelope(for: metadata, signingKey: signingKey)

    let outcome = UpdateMetadataVerifier.verify(
      envelopeData: envelope,
      publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(),
      installedVersion: AppVersion("1.0.0")!,
      currentSystemVersion: AppVersion("14.0.0")!
    )

    #expect(outcome == .available(metadata))
  }

  @Test
  func givenATamperedPayload_whenVerified_thenTheSignatureIsRejected() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let metadata = UpdateMetadataVerifierTests.metadata(version: "2.0.0")
    let payloadBytes = try JSONEncoder().encode(metadata)
    let signature = try signingKey.signature(for: payloadBytes)
    var tamperedPayloadBytes = payloadBytes
    tamperedPayloadBytes[0] ^= 0xFF
    let envelope: [String: String] = [
      "payload": tamperedPayloadBytes.base64EncodedString(),
      "signature": signature.base64EncodedString(),
    ]
    let envelopeData = try JSONSerialization.data(withJSONObject: envelope)

    let outcome = UpdateMetadataVerifier.verify(
      envelopeData: envelopeData,
      publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(),
      installedVersion: AppVersion("1.0.0")!,
      currentSystemVersion: AppVersion("14.0.0")!
    )

    #expect(outcome == .rejected(.invalidSignature))
  }

  @Test
  func givenAMissingOrEmptySignature_whenVerified_thenTheSignatureIsRejected() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let metadata = UpdateMetadataVerifierTests.metadata(version: "2.0.0")
    let payloadBytes = try JSONEncoder().encode(metadata)
    let envelope: [String: String] = [
      "payload": payloadBytes.base64EncodedString(),
      "signature": "",
    ]
    let envelopeData = try JSONSerialization.data(withJSONObject: envelope)

    let outcome = UpdateMetadataVerifier.verify(
      envelopeData: envelopeData,
      publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(),
      installedVersion: AppVersion("1.0.0")!,
      currentSystemVersion: AppVersion("14.0.0")!
    )

    #expect(outcome == .rejected(.invalidSignature))
  }

  @Test
  func givenMalformedEnvelopeJSON_whenVerified_thenMetadataIsMalformed() {
    let signingKey = Curve25519.Signing.PrivateKey()
    let envelopeData = Data("not json".utf8)

    let outcome = UpdateMetadataVerifier.verify(
      envelopeData: envelopeData,
      publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(),
      installedVersion: AppVersion("1.0.0")!,
      currentSystemVersion: AppVersion("14.0.0")!
    )

    #expect(outcome == .rejected(.malformed))
  }

  @Test
  func givenAnUnsupportedFormatVersion_whenVerified_thenItIsIncompatible() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let metadata = UpdateMetadataVerifierTests.metadata(version: "2.0.0", formatVersion: 99)
    let envelope = try UpdateMetadataVerifierTests.envelope(for: metadata, signingKey: signingKey)

    let outcome = UpdateMetadataVerifier.verify(
      envelopeData: envelope,
      publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(),
      installedVersion: AppVersion("1.0.0")!,
      currentSystemVersion: AppVersion("14.0.0")!
    )

    #expect(outcome == .rejected(.incompatibleFormatVersion))
  }

  @Test
  func givenAMinimumSystemVersionAboveTheCurrentSystem_whenVerified_thenItIsIncompatible() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let metadata = UpdateMetadataVerifierTests.metadata(
      version: "2.0.0",
      minimumSystemVersion: "99.0.0"
    )
    let envelope = try UpdateMetadataVerifierTests.envelope(for: metadata, signingKey: signingKey)

    let outcome = UpdateMetadataVerifier.verify(
      envelopeData: envelope,
      publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(),
      installedVersion: AppVersion("1.0.0")!,
      currentSystemVersion: AppVersion("14.0.0")!
    )

    #expect(outcome == .rejected(.incompatibleSystemVersion))
  }

  @Test
  func givenAValidlySignedButNotNewerVersion_whenVerified_thenItIsUpToDate() throws {
    let signingKey = Curve25519.Signing.PrivateKey()
    let metadata = UpdateMetadataVerifierTests.metadata(version: "1.0.0")
    let envelope = try UpdateMetadataVerifierTests.envelope(for: metadata, signingKey: signingKey)

    let outcome = UpdateMetadataVerifier.verify(
      envelopeData: envelope,
      publicKeyBase64: signingKey.publicKey.rawRepresentation.base64EncodedString(),
      installedVersion: AppVersion("1.0.0")!,
      currentSystemVersion: AppVersion("14.0.0")!
    )

    #expect(outcome == .upToDate)
  }

  private static func metadata(
    version: String,
    formatVersion: Int = 1,
    minimumSystemVersion: String = "13.0.0"
  ) -> UpdateMetadata {
    UpdateMetadata(
      formatVersion: formatVersion,
      version: version,
      minimumSystemVersion: minimumSystemVersion,
      downloadURL: URL(string: "https://example.com/CrazyFileManager.dmg")!,
      releaseNotesURL: URL(string: "https://example.com/release-notes")!,
      artifactSHA256Hex: "test-hash"
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
}
