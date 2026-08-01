import Foundation

struct ScanCachePresentation: Equatable {
  let title: String
  let detail: String
  let scanActionTitle: String
  let clearActionTitle: String?

  static func savedResults(
    scopeTitle: String,
    completedAt: Date,
    expiresAt: Date,
    locale: Locale = .autoupdatingCurrent,
    timeZone: TimeZone = .autoupdatingCurrent
  ) -> Self {
    let completedTimestamp = formattedTimestamp(
      completedAt,
      locale: locale,
      timeZone: timeZone
    )
    let expiryTimestamp = formattedTimestamp(
      expiresAt,
      locale: locale,
      timeZone: timeZone
    )
    return Self(
      title: "Saved scan results",
      detail:
        "\(scopeTitle) was scanned on \(completedTimestamp). "
        + "Saved results expire on \(expiryTimestamp).",
      scanActionTitle: "Rescan",
      clearActionTitle: "Clear Scan Data"
    )
  }

  static func notice(_ notice: ScanCacheNotice) -> Self {
    if notice == .expired {
      return Self(
        title: "Saved scan results expired",
        detail: notice.message,
        scanActionTitle: "Scan Again",
        clearActionTitle: nil
      )
    }
    if notice == .cleanupFailed {
      return Self(
        title: "Saved scan data needs attention",
        detail: notice.message,
        scanActionTitle: "Scan",
        clearActionTitle: nil
      )
    }
    if notice == .reconstructed {
      return Self(
        title: "Saved scan data was rebuilt",
        detail: notice.message,
        scanActionTitle: "Scan",
        clearActionTitle: nil
      )
    }
    return Self(
      title: "Saved scan data needs attention",
      detail: notice.message,
      scanActionTitle: "Scan",
      clearActionTitle: nil
    )
  }

  static func clearControl(
    hasCompletedResults: Bool,
    scanState: ScanState
  ) -> ScanCacheClearControl? {
    guard hasCompletedResults else {
      return nil
    }
    return ScanCacheClearControl(
      title: "Clear Scan Data",
      isEnabled: !isActive(scanState)
    )
  }

  private static func formattedTimestamp(
    _ date: Date,
    locale: Locale,
    timeZone: TimeZone
  ) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
    return formatter.string(from: date)
  }

  private static func isActive(_ scanState: ScanState) -> Bool {
    switch scanState {
    case .scanning, .paused, .resuming, .cancelling:
      true
    case .idle, .cancelled, .completed, .failed:
      false
    }
  }
}

struct ScanCacheClearControl: Equatable {
  let title: String
  let isEnabled: Bool
}
