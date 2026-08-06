import XCTest

final class FocusRestorationUITests: XCTestCase {
  @MainActor
  func
    test_givenAnOpenTrashConfirmationDialog_whenDismissedWithEscape_thenTheTriggeringRowRegainsFocus()
  {
    let application = launchApplication(scenario: "trashEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    let row = outline.cells["notes.txt"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.click()
    application.typeKey(.delete, modifierFlags: .command)
    XCTAssertTrue(application.staticTexts["Move to Trash?"].waitForExistence(timeout: 3))
    application.typeKey(.escape, modifierFlags: [])
    XCTAssertFalse(application.staticTexts["Move to Trash?"].waitForExistence(timeout: 2))

    application.typeKey(.delete, modifierFlags: .command)

    XCTAssertTrue(application.staticTexts["Move to Trash?"].waitForExistence(timeout: 3))
  }

  @MainActor
  func
    test_givenInlineRenameIsCancelled_whenEscapeIsPressed_thenTheRenamedRowRegainsFocus()
  {
    let application = launchApplication(scenario: "cachedResultsRenameEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    let row = outline.cells["notes.txt"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.click()
    application.typeKey(.return, modifierFlags: [])
    let renameField = application.textFields["renameField"]
    XCTAssertTrue(renameField.waitForExistence(timeout: 3))
    application.typeKey(.escape, modifierFlags: [])
    XCTAssertFalse(application.textFields["renameField"].waitForExistence(timeout: 2))

    application.typeKey(.return, modifierFlags: [])

    XCTAssertTrue(application.textFields["renameField"].waitForExistence(timeout: 3))
  }

  @MainActor
  func
    test_givenInlineRenameIsCancelledInAllItemsMode_whenEscapeIsPressed_thenTheRenamedRowRegainsFocus()
  {
    let application = launchApplication(scenario: "cachedResultsRenameEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    application.radioButtons["All Items"].click()
    let table = application.tables["allItemsTable"]
    XCTAssertTrue(table.waitForExistence(timeout: 3))
    let row = table.cells["notes.txt"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.click()
    application.typeKey(.return, modifierFlags: [])
    let renameField = application.textFields["renameField"]
    XCTAssertTrue(renameField.waitForExistence(timeout: 3))
    application.typeKey(.escape, modifierFlags: [])
    XCTAssertFalse(application.textFields["renameField"].waitForExistence(timeout: 2))

    application.typeKey(.return, modifierFlags: [])

    XCTAssertTrue(application.textFields["renameField"].waitForExistence(timeout: 3))
  }

  @MainActor
  func
    test_givenTheRootFolderIsSelected_whenItIsCollapsedAndExpanded_thenItRemainsSelected()
  {
    let application = launchApplication(scenario: "allItemsEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    let rootRow = outline.cells["debugger"]
    XCTAssertTrue(rootRow.waitForExistence(timeout: 3))
    rootRow.click()
    XCTAssertTrue(rootRow.isSelected)

    application.typeKey(.leftArrow, modifierFlags: [])
    XCTAssertFalse(outline.cells["Documents"].waitForExistence(timeout: 2))
    application.typeKey(.rightArrow, modifierFlags: [])

    XCTAssertTrue(outline.cells["Documents"].waitForExistence(timeout: 3))
    XCTAssertTrue(outline.cells["debugger"].isSelected)
  }

  @MainActor
  private func launchApplication(scenario: String = "empty") -> XCUIApplication {
    let application = XCUIApplication()
    application.terminate()
    application.launchArguments = [
      "-ApplePersistenceIgnoreState",
      "YES",
    ]
    application.launchArguments += [
      "-uiScenario",
      scenario,
      "-AppleLocale",
      "en_US_POSIX",
    ]
    application.launchEnvironment["TZ"] = "GMT"
    application.launch()
    return application
  }
}
