actor ScanExecutionControl {
  private enum Mode {
    case running
    case paused
    case cancelled
  }

  private var mode = Mode.running
  private var waiter: CheckedContinuation<Void, any Error>?

  func pause() -> Bool {
    guard mode == .running else {
      return false
    }
    mode = .paused
    return true
  }

  func resume() -> Bool {
    guard mode == .paused else {
      return false
    }
    mode = .running
    waiter?.resume()
    waiter = nil
    return true
  }

  func cancel() {
    guard mode != .cancelled else {
      return
    }
    mode = .cancelled
    waiter?.resume(throwing: CancellationError())
    waiter = nil
  }

  func waitUntilRunning() async throws {
    try Task.checkCancellation()
    switch mode {
    case .running:
      return
    case .cancelled:
      throw CancellationError()
    case .paused:
      try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          switch mode {
          case .running:
            continuation.resume()
          case .paused:
            waiter = continuation
          case .cancelled:
            continuation.resume(throwing: CancellationError())
          }
        }
      } onCancel: {
        Task {
          await self.cancel()
        }
      }
      try Task.checkCancellation()
    }
  }
}
