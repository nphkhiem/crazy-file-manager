import Foundation

struct FoundationRenameExecutor: RenameExecuting {
  func rename(at path: String, to newName: String) throws -> String {
    let sourceURL = URL(filePath: path)
    let destinationURL = sourceURL.deletingLastPathComponent()
      .appending(path: newName)
    let coordinator = NSFileCoordinator()
    var coordinationError: NSError?
    var moveError: (any Error)?
    coordinator.coordinate(
      writingItemAt: sourceURL,
      options: .forMoving,
      writingItemAt: destinationURL,
      options: .forReplacing,
      error: &coordinationError
    ) { coordinatedSourceURL, coordinatedDestinationURL in
      do {
        try FileManager.default.moveItem(
          at: coordinatedSourceURL,
          to: coordinatedDestinationURL
        )
      } catch {
        moveError = error
      }
    }
    if let coordinationError {
      throw coordinationError
    }
    if let moveError {
      throw moveError
    }
    return destinationURL.path(percentEncoded: false)
  }
}
