import CryptoKit
import Foundation

enum UpdateMetadataVerifier {
  static let supportedFormatVersion = 1

  static func verify(
    envelopeData: Data,
    publicKeyBase64: String,
    installedVersion: AppVersion,
    currentSystemVersion: AppVersion
  ) -> UpdateCheckOutcome {
    guard
      let envelope = try? JSONSerialization.jsonObject(with: envelopeData) as? [String: String],
      let payloadBase64 = envelope["payload"],
      let signatureBase64 = envelope["signature"],
      let payloadBytes = Data(base64Encoded: payloadBase64),
      let signatureBytes = Data(base64Encoded: signatureBase64),
      let publicKeyBytes = Data(base64Encoded: publicKeyBase64),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyBytes)
    else {
      return .rejected(.malformed)
    }

    guard !signatureBytes.isEmpty, publicKey.isValidSignature(signatureBytes, for: payloadBytes)
    else {
      return .rejected(.invalidSignature)
    }

    guard let metadata = try? JSONDecoder().decode(UpdateMetadata.self, from: payloadBytes) else {
      return .rejected(.malformed)
    }

    guard metadata.formatVersion == supportedFormatVersion else {
      return .rejected(.incompatibleFormatVersion)
    }

    guard let metadataVersion = AppVersion(metadata.version) else {
      return .rejected(.malformed)
    }

    guard let minimumSystemVersion = AppVersion(metadata.minimumSystemVersion) else {
      return .rejected(.malformed)
    }

    guard minimumSystemVersion <= currentSystemVersion else {
      return .rejected(.incompatibleSystemVersion)
    }

    guard metadataVersion > installedVersion else {
      return .upToDate
    }

    return .available(metadata)
  }
}
