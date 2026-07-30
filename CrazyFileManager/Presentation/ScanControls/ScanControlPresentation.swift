enum ScanPrimaryAction: Equatable {
  case pause
  case resume
  case rescan
}

struct ScanControlPresentation: Equatable {
  let primaryAction: ScanPrimaryAction?
  let isPrimaryEnabled: Bool
  let showsCancel: Bool
  let isCancelEnabled: Bool

  static func resolve(for state: ScanState) -> Self {
    switch state {
    case .idle:
      Self(
        primaryAction: nil,
        isPrimaryEnabled: false,
        showsCancel: false,
        isCancelEnabled: false
      )
    case .scanning:
      Self(
        primaryAction: .pause,
        isPrimaryEnabled: true,
        showsCancel: true,
        isCancelEnabled: true
      )
    case .paused:
      Self(
        primaryAction: .resume,
        isPrimaryEnabled: true,
        showsCancel: true,
        isCancelEnabled: true
      )
    case .resuming:
      Self(
        primaryAction: .resume,
        isPrimaryEnabled: false,
        showsCancel: true,
        isCancelEnabled: true
      )
    case .cancelling:
      Self(
        primaryAction: nil,
        isPrimaryEnabled: false,
        showsCancel: true,
        isCancelEnabled: false
      )
    case .cancelled, .completed, .failed:
      Self(
        primaryAction: .rescan,
        isPrimaryEnabled: true,
        showsCancel: false,
        isCancelEnabled: false
      )
    }
  }
}

enum ScanProgressPresentation: Equatable {
  case hidden
  case indeterminate
  case determinate(Double)

  static func resolve(for state: ScanState) -> Self {
    let progress: ScanProgress
    switch state {
    case .scanning(let value),
      .paused(let value),
      .resuming(let value),
      .cancelling(let value):
      progress = value
    case .idle, .cancelled, .completed, .failed:
      return .hidden
    }

    guard let fraction = progress.fractionCompleted, fraction.isFinite else {
      return .indeterminate
    }
    return .determinate(min(max(fraction, 0), 1))
  }
}
