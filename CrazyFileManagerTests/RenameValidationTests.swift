import Testing

@testable import CrazyFileManager

struct RenameValidationTests {
  @Test
  func givenEmptyProposedName_whenValidated_thenErrorIsEmpty() {
    let error = RenameValidation.validate(
      currentName: "report.pdf",
      proposedName: "",
      siblingNames: []
    )
    #expect(error == .empty)
  }

  @Test
  func givenNameContainingSlash_whenValidated_thenErrorIsContainsPathSeparator() {
    let error = RenameValidation.validate(
      currentName: "report.pdf",
      proposedName: "a/b",
      siblingNames: []
    )
    #expect(error == .containsPathSeparator)
  }

  @Test
  func givenNameContainingColon_whenValidated_thenErrorIsContainsPathSeparator() {
    let error = RenameValidation.validate(
      currentName: "report.pdf",
      proposedName: "a:b",
      siblingNames: []
    )
    #expect(error == .containsPathSeparator)
  }

  @Test
  func givenDotAsProposedName_whenValidated_thenErrorIsDotOrDotDot() {
    let error = RenameValidation.validate(
      currentName: "report.pdf",
      proposedName: ".",
      siblingNames: []
    )
    #expect(error == .isDotOrDotDot)
  }

  @Test
  func givenDotDotAsProposedName_whenValidated_thenErrorIsDotOrDotDot() {
    let error = RenameValidation.validate(
      currentName: "report.pdf",
      proposedName: "..",
      siblingNames: []
    )
    #expect(error == .isDotOrDotDot)
  }

  @Test
  func givenNameContainingNullCharacter_whenValidated_thenErrorIsInvalidPlatformName() {
    let error = RenameValidation.validate(
      currentName: "report.pdf",
      proposedName: "a\0b",
      siblingNames: []
    )
    #expect(error == .invalidPlatformName)
  }

  @Test
  func givenNameCollidingWithASibling_whenValidated_thenErrorIsCollidesWithExistingName() {
    let error = RenameValidation.validate(
      currentName: "report.pdf",
      proposedName: "notes.txt",
      siblingNames: ["notes.txt", "photo.png"]
    )
    #expect(error == .collidesWithExistingName)
  }

  @Test
  func givenNameEqualToItsOwnCurrentName_whenValidated_thenNoErrorOccurs() {
    let error = RenameValidation.validate(
      currentName: "report.pdf",
      proposedName: "report.pdf",
      siblingNames: ["report.pdf", "photo.png"]
    )
    #expect(error == nil)
  }

  @Test
  func givenUnicodeName_whenValidated_thenNoErrorOccurs() {
    let error = RenameValidation.validate(
      currentName: "report.pdf",
      proposedName: "Café Notes café.pdf",
      siblingNames: []
    )
    #expect(error == nil)
  }

  @Test
  func givenChangedExtension_whenCheckingConfirmationRequirement_thenConfirmationIsRequired() {
    let requires = RenameValidation.requiresExtensionChangeConfirmation(
      currentName: "report.pdf",
      proposedName: "report.txt"
    )
    #expect(requires)
  }

  @Test
  func givenUnchangedExtension_whenCheckingConfirmationRequirement_thenConfirmationIsNotRequired() {
    let requires = RenameValidation.requiresExtensionChangeConfirmation(
      currentName: "report.pdf",
      proposedName: "final report.pdf"
    )
    #expect(!requires)
  }

  @Test
  func
    givenExtensionAddedToAnExtensionlessName_whenCheckingConfirmationRequirement_thenConfirmationIsRequired()
  {
    let requires = RenameValidation.requiresExtensionChangeConfirmation(
      currentName: "README",
      proposedName: "README.txt"
    )
    #expect(requires)
  }

  @Test
  func givenExtensionRemoved_whenCheckingConfirmationRequirement_thenConfirmationIsRequired() {
    let requires = RenameValidation.requiresExtensionChangeConfirmation(
      currentName: "report.pdf",
      proposedName: "report"
    )
    #expect(requires)
  }
}
