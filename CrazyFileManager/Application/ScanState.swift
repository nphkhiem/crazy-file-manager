struct ScanFailure: Equatable, Sendable {
  let message: String
}

enum QuitDisposition: Equatable, Sendable {
  case terminateNow
  case confirmScanCancellation
}

enum ScanState: Equatable, Sendable {
  case idle
  case scanning(ScanProgress)
  case paused(ScanProgress)
  case resuming(ScanProgress)
  case cancelling(ScanProgress)
  case cancelled
  case completed(ScanCompletion)
  case failed(ScanFailure)
}
