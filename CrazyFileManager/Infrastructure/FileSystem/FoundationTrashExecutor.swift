import Foundation

struct FoundationTrashExecutor: TrashExecuting {
  func trash(at path: String) throws {
    try FileManager.default.trashItem(
      at: URL(filePath: path),
      resultingItemURL: nil
    )
  }
}
