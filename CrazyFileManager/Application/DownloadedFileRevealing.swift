import Foundation

protocol DownloadedFileRevealing: Sendable {
  func reveal(_ fileURL: URL)
}
