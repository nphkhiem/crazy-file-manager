struct AppVersion: Comparable, Equatable, Sendable {
  let components: [Int]

  init?(_ string: String) {
    guard !string.isEmpty else { return nil }
    var parsedComponents: [Int] = []
    for part in string.split(separator: ".", omittingEmptySubsequences: false) {
      guard let value = Int(part) else { return nil }
      parsedComponents.append(value)
    }
    components = parsedComponents
  }

  static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
    let count = max(lhs.components.count, rhs.components.count)
    for index in 0..<count {
      let lhsValue = index < lhs.components.count ? lhs.components[index] : 0
      let rhsValue = index < rhs.components.count ? rhs.components[index] : 0
      if lhsValue != rhsValue {
        return lhsValue < rhsValue
      }
    }
    return false
  }
}
