import Foundation

struct FoundationMutationEvidenceProvider: MutationEvidenceProviding {
  func liveEvidence(at path: String) -> LiveMutationEvidence? {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: path),
      let deviceNumber = attributes[.systemNumber] as? Int,
      let inodeNumber = attributes[.systemFileNumber] as? Int
    else {
      return nil
    }
    let url = URL(filePath: path)
    let parentPath = url.deletingLastPathComponent().path(percentEncoded: false)
    let volumeIdentifier = try? url.resourceValues(forKeys: [.volumeUUIDStringKey])
      .volumeUUIDString
    return LiveMutationEvidence(
      deviceNumber: deviceNumber,
      inodeNumber: inodeNumber,
      parentPath: parentPath,
      volumeIdentifier: volumeIdentifier
    )
  }
}
