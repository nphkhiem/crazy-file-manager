import Foundation

@testable import CrazyFileManager

final class ControlledDownloadedFileRevealing: DownloadedFileRevealing, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var revealedURLs: [URL] = []

  func reveal(_ fileURL: URL) {
    lock.withLock { revealedURLs.append(fileURL) }
  }
}
