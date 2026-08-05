import Foundation

@testable import CrazyFileManager

final class ControlledUpdateCheckPreferencesStoring:
  UpdateCheckPreferencesStoring,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var storedValue: Bool

  init(isAutomaticCheckEnabled: Bool = false) {
    storedValue = isAutomaticCheckEnabled
  }

  var isAutomaticCheckEnabled: Bool {
    get { lock.withLock { storedValue } }
    set { lock.withLock { storedValue = newValue } }
  }
}
