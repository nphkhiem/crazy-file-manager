import Foundation

protocol TrashExecuting: Sendable {
  func trash(at path: String) throws
}

enum TrashOperation {
  static func perform(
    expected: ExpectedMutationTarget,
    liveEvidenceProvider: any MutationEvidenceProviding,
    executor: any TrashExecuting
  ) -> TrashOutcome {
    guard
      case .accepted = MutationPreflight.validate(
        expected: expected,
        liveEvidenceProvider: liveEvidenceProvider
      )
    else {
      return .stale(reason: "This item can no longer be found.")
    }
    guard Self.liveSafetyState(at: expected.path, kind: expected.kind) == .normal else {
      return .stale(reason: "This item is no longer eligible to move to Trash.")
    }
    guard Self.isWritable(at: expected.path) else {
      return .stale(reason: "This item can’t be modified right now.")
    }
    do {
      try executor.trash(at: expected.path)
      return .trashed
    } catch {
      return .failed(reason: "This item couldn’t be moved to Trash.")
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

  private static func isWritable(at path: String) -> Bool {
    (try? URL(filePath: path).resourceValues(forKeys: [.isWritableKey]))?.isWritable ?? false
  }
}
