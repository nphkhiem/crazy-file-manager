enum PathRelocation {
  static func rewritten(_ path: String, oldPrefix: String, newPrefix: String) -> String {
    if path == oldPrefix {
      return newPrefix
    }
    let normalizedOldPrefix = oldPrefix.hasSuffix("/") ? String(oldPrefix.dropLast()) : oldPrefix
    let normalizedNewPrefix = newPrefix.hasSuffix("/") ? String(newPrefix.dropLast()) : newPrefix
    guard path.hasPrefix(normalizedOldPrefix + "/") else {
      return path
    }
    return normalizedNewPrefix + path.dropFirst(normalizedOldPrefix.count)
  }
}
