import Foundation

struct ScanDataSettingsPresentation: Equatable {
  let sizeText: String
  let scopeText: String?
  let completedText: String?
  let expiresText: String?
  let isClearEnabled: Bool

  static func resolve(
    cacheFileSizeBytes: Int64?,
    completedScopeDescription: ScanScopeDescription?,
    completedAt: Date?,
    expiresAt: Date?,
    locale: Locale = .autoupdatingCurrent,
    timeZone: TimeZone = .autoupdatingCurrent
  ) -> Self {
    let sizeText =
      cacheFileSizeBytes.map {
        $0.formatted(.byteCount(style: .file).locale(locale))
      } ?? "No saved scan data"
    let scopeText = completedScopeDescription.map { ScanScopePresentation.resolve($0).title }
    let completedText = completedAt.map {
      formattedTimestamp($0, locale: locale, timeZone: timeZone)
    }
    let expiresText = expiresAt.map { formattedTimestamp($0, locale: locale, timeZone: timeZone) }
    return Self(
      sizeText: sizeText,
      scopeText: scopeText,
      completedText: completedText,
      expiresText: expiresText,
      isClearEnabled: completedScopeDescription != nil
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
}
