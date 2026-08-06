import XCTest

final class KeyboardOperabilityUITests: XCTestCase {
  @MainActor
  func
    test_givenTrashEligibleScenario_whenCommandDeleteIsPressedOnASelectedRow_thenAConfirmationDialogShowsNameAndPath()
  {
    let application = launchApplication(scenario: "trashEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    let row = outline.cells["notes.txt"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.click()

    application.typeKey(.delete, modifierFlags: .command)

    XCTAssertTrue(application.staticTexts["Move to Trash?"].waitForExistence(timeout: 3))
    let messagePredicate = NSPredicate(format: "value BEGINSWITH[c] %@", "notes.txt")
    XCTAssertTrue(
      application.staticTexts.matching(messagePredicate).firstMatch.waitForExistence(timeout: 3)
    )
  }

  @MainActor
  func
    test_givenTrashEligibleScenario_whenCommandDeleteIsPressedInAllItemsMode_thenAConfirmationDialogShowsNameAndPath()
  {
    let application = launchApplication(scenario: "trashEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    application.radioButtons["All Items"].click()
    let table = application.tables["allItemsTable"]
    XCTAssertTrue(table.waitForExistence(timeout: 3))
    let row = table.cells["notes.txt"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.click()

    application.typeKey(.delete, modifierFlags: .command)

    XCTAssertTrue(application.staticTexts["Move to Trash?"].waitForExistence(timeout: 3))
    let messagePredicate = NSPredicate(format: "value BEGINSWITH[c] %@", "notes.txt")
    XCTAssertTrue(
      application.staticTexts.matching(messagePredicate).firstMatch.waitForExistence(timeout: 3)
    )
  }

  @MainActor
  func
    test_givenRenameEligibleScenario_whenReturnIsPressedOnASelectedRow_thenInlineEditingBeginsWithoutMutating()
  {
    let application = launchApplication(scenario: "cachedResultsRenameEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    let row = outline.cells["notes.txt"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.click()

    application.typeKey(.return, modifierFlags: [])

    XCTAssertTrue(application.textFields["renameField"].waitForExistence(timeout: 3))
  }

  @MainActor
  func
    test_givenAnOpenTrashConfirmationDialog_whenEscapeIsPressed_thenTheDialogDismissesWithoutTrashing()
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
    XCTAssertTrue(row.waitForExistence(timeout: 3))
  }

  @MainActor
  func
    test_givenAllItemsModeIsActive_whenCommandFIsPressed_thenTheSearchFieldReceivesFocus()
  {
    let application = launchApplication(scenario: "allItemsEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    application.radioButtons["All Items"].click()
    let table = application.tables["allItemsTable"]
    XCTAssertTrue(table.waitForExistence(timeout: 3))
    let searchField = application.textFields["allItemsSearchField"]
    XCTAssertTrue(searchField.waitForExistence(timeout: 3))

    application.typeKey("f", modifierFlags: .command)
    application.typeText("cloud")

    XCTAssertTrue(table.cells["cloud.txt"].waitForExistence(timeout: 3))
    XCTAssertFalse(table.cells["visible.txt"].exists)
    XCTAssertFalse(table.cells["Documents"].exists)
    XCTAssertEqual(searchField.value as? String, "cloud")
  }

  @MainActor
  func
    test_givenTheAllItemsSearchFieldIsFocused_whenTabIsPressed_thenFocusMovesAwayWithoutBeingTrapped()
  {
    let application = launchApplication(scenario: "allItemsEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    application.radioButtons["All Items"].click()
    let searchField = application.textFields["allItemsSearchField"]
    XCTAssertTrue(searchField.waitForExistence(timeout: 3))
    application.typeKey("f", modifierFlags: .command)
    application.typeText("first")
    XCTAssertEqual(searchField.value as? String, "first")

    application.typeKey(.tab, modifierFlags: [])
    application.typeText("second")

    XCTAssertEqual(searchField.value as? String, "first")
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
