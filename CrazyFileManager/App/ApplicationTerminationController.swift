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

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let launchWindowSize = Self.launchWindowSizeOverride else {
      return
    }
    for window in NSApplication.shared.windows {
      window.setContentSize(launchWindowSize)
    }
  }

  private static var launchWindowSizeOverride: NSSize? {
    let arguments = ProcessInfo.processInfo.arguments
    guard
      let width = launchArgumentValue(named: "-uiWindowWidth", in: arguments),
      let height = launchArgumentValue(named: "-uiWindowHeight", in: arguments)
    else {
      return nil
    }
    return NSSize(width: width, height: height)
  }

  private static func launchArgumentValue(
    named argument: String,
    in arguments: [String]
  ) -> Double? {
    guard
      let index = arguments.firstIndex(of: argument),
      arguments.indices.contains(arguments.index(after: index))
    else {
      return nil
    }
    return Double(arguments[arguments.index(after: index)])
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
