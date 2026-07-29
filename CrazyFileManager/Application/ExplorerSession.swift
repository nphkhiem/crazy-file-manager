import Foundation
import Observation

@MainActor
@Observable
final class ExplorerSession {
  private(set) var selectedScope: ScanScope
  private(set) var scanState: ScanState = .idle

  init(homeDirectoryURL: URL) {
    selectedScope = .homeFolder(homeDirectoryURL)
  }
}
