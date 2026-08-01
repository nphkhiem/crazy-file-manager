import AppKit

@MainActor
final class ApplicationTerminationController: NSObject, NSApplicationDelegate {
  weak var session: ExplorerSession?

  private let requestTermination: @MainActor () -> Void
  private var allowsNextTermination = false

  override init() {
    requestTermination = {
      NSApplication.shared.terminate(nil)
    }
    super.init()
  }

  init(requestTermination: @escaping @MainActor () -> Void) {
    self.requestTermination = requestTermination
    super.init()
  }

  func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    if allowsNextTermination {
      allowsNextTermination = false
      return .terminateNow
    }
    guard let session else {
      return .terminateNow
    }
    switch session.requestQuit() {
    case .terminateNow:
      return .terminateNow
    case .confirmScanCancellation:
      return .terminateCancel
    }
  }

  func completeConfirmedTermination() {
    allowsNextTermination = true
    requestTermination()
  }
}
