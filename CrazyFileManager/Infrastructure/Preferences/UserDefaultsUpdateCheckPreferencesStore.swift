import Foundation

final class UserDefaultsUpdateCheckPreferencesStore:
  UpdateCheckPreferencesStoring,
  @unchecked Sendable
{
  private static let storageKey = "isAutomaticUpdateCheckEnabled"

  private let defaults: UserDefaults
  private let lock = NSLock()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var isAutomaticCheckEnabled: Bool {
    get {
      lock.withLock { defaults.bool(forKey: Self.storageKey) }
    }
    set {
      lock.withLock { defaults.set(newValue, forKey: Self.storageKey) }
    }
  }
}
