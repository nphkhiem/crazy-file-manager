struct UpdateCheckOutcomePresentation: Equatable {
  let title: String
  let detail: String?

  static func resolve(_ outcome: UpdateCheckOutcome?) -> Self? {
    guard let outcome else { return nil }
    switch outcome {
    case .upToDate:
      return Self(title: "You’re up to date", detail: nil)
    case .available(let metadata):
      return Self(title: "Version \(metadata.version) is available", detail: nil)
    case .rejected(let reason):
      return Self(title: title(for: reason), detail: nil)
    case .networkFailure(let message):
      return Self(title: "Couldn’t check for updates", detail: message)
    }
  }

  private static func title(for reason: UpdateMetadataRejection) -> String {
    switch reason {
    case .invalidSignature:
      "This update couldn’t be verified"
    case .malformed:
      "This update’s information was unreadable"
    case .incompatibleFormatVersion:
      "This update requires a newer version of Crazy File Manager"
    case .incompatibleSystemVersion:
      "This update requires a newer version of macOS"
    }
  }
}
