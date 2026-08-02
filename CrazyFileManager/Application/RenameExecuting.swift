import Foundation

protocol RenameExecuting: Sendable {
  func rename(at path: String, to newName: String) throws -> String
}

enum RenameOperation {
  static func perform(
    expected: ExpectedMutationTarget,
    proposedName: String,
    liveEvidenceProvider: any MutationEvidenceProviding,
    executor: any RenameExecuting
  ) -> RenameOutcome {
    guard
      case .accepted = MutationPreflight.validate(
        expected: expected,
        liveEvidenceProvider: liveEvidenceProvider
      )
    else {
      return .rejected(reason: "This item can no longer be found.")
    }
    guard Self.liveSafetyState(at: expected.path, kind: expected.kind) == .normal else {
      return .rejected(reason: "This item is no longer eligible to rename.")
    }
    do {
      let newPath = try executor.rename(at: expected.path, to: proposedName)
      return .renamed(newPath: newPath)
    } catch {
      return .rejected(reason: "This item couldn’t be renamed.")
    }
  }

  private static func liveSafetyState(
    at path: String,
    kind: StorageItemKind
  ) -> ItemSafetyState {
    let url = URL(filePath: path)
    let volumeValues = try? url.resourceValues(forKeys: [
      .volumeIsInternalKey,
      .volumeIsReadOnlyKey,
      .volumeIsRemovableKey,
    ])
    let volume = ScanVolumeCharacteristics(
      isInternal: volumeValues?.volumeIsInternal,
      isReadOnly: volumeValues?.volumeIsReadOnly,
      isRemovable: volumeValues?.volumeIsRemovable
    )
    let linkCount = (try? url.resourceValues(forKeys: [.linkCountKey]))?.linkCount ?? 1
    return RestrictionPolicy.classify(
      path: path,
      kind: kind,
      isRoot: false,
      isPackageDescendant: false,
      isShared: linkCount > 1,
      volume: volume
    )
  }
}
