import AppKit

struct WorkspaceDownloadedFileRevealer: DownloadedFileRevealing {
  func reveal(_ fileURL: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
  }
}
