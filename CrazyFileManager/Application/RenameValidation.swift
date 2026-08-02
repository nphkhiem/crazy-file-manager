import Foundation

enum RenameValidation {
  static func validate(
    currentName: String,
    proposedName: String,
    siblingNames: Set<String>
  ) -> RenameValidationError? {
    guard !proposedName.isEmpty else {
      return .empty
    }
    guard !proposedName.contains("/"), !proposedName.contains(":") else {
      return .containsPathSeparator
    }
    guard proposedName != ".", proposedName != ".." else {
      return .isDotOrDotDot
    }
    guard !proposedName.contains("\0") else {
      return .invalidPlatformName
    }
    if proposedName != currentName, siblingNames.contains(proposedName) {
      return .collidesWithExistingName
    }
    return nil
  }

  static func requiresExtensionChangeConfirmation(
    currentName: String,
    proposedName: String
  ) -> Bool {
    (currentName as NSString).pathExtension != (proposedName as NSString).pathExtension
  }
}
