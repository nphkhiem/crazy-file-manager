struct ScanFailure: Equatable, Sendable {
  let message: String
}

enum ScanState: Equatable, Sendable {
  case idle
  case scanning(ScanProgress)
  case completed(ScanCompletion)
  case failed(ScanFailure)
}
