import Foundation

enum RenameValidationError: Equatable, Sendable {
  case empty
  case containsPathSeparator
  case isDotOrDotDot
  case invalidPlatformName
  case collidesWithExistingName
}

struct RenamePlan: Equatable, Sendable {
  let currentPath: String
  let parentPath: String
  let proposedName: String
  let requiresExtensionChangeConfirmation: Bool
}

enum RenameOutcome: Equatable, Sendable {
  case renamed(newPath: String)
  case rejected(reason: String)
}
