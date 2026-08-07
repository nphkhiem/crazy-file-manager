import XCTest

final class LargeResultSetKeyboardUITests: XCTestCase {
  @MainActor
  func
    test_givenManyItems_whenARowFarBelowTheFoldIsSelected_thenItsLabelReflectsItsOwnRowNotARecycledOne()
  {
    let application = launchApplication(scenario: "largeKeyboardTraversal")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 5))
    let firstRow = outline.cells["item-0000.bin"]
    XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
    firstRow.click()

    scrollDown(application, times: 8)

    let farRow = outline.cells["item-0250.bin"]
    XCTAssertTrue(farRow.waitForExistence(timeout: 10))
    farRow.click()

    XCTAssertTrue(farRow.isSelected)
    XCTAssertFalse(outline.cells["item-0000.bin"].isSelected)
    let nameCell = application.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "item-0250.bin"))
      .firstMatch
    XCTAssertTrue(nameCell.waitForExistence(timeout: 3))
  }

  @MainActor
  func
    test_givenManyItems_whenARowFarBelowTheFoldIsSelected_thenCommandDeleteTargetsThatExactRowNotAStaleRecycledOne()
  {
    let application = launchApplication(scenario: "largeKeyboardTraversal")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 5))
    let firstRow = outline.cells["item-0000.bin"]
    XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
    firstRow.click()

    scrollDown(application, times: 8)

    let farRow = outline.cells["item-0280.bin"]
    XCTAssertTrue(farRow.waitForExistence(timeout: 10))
    farRow.click()
    XCTAssertTrue(farRow.isSelected)
    XCTAssertTrue(application.staticTexts["item-0280.bin"].waitForExistence(timeout: 3))

    application.typeKey(.delete, modifierFlags: .command)

    XCTAssertTrue(application.staticTexts["Move to Trash?"].waitForExistence(timeout: 3))
    let messagePredicate = NSPredicate(format: "value BEGINSWITH[c] %@", "item-0280.bin")
    XCTAssertTrue(
      application.staticTexts.matching(messagePredicate).firstMatch.waitForExistence(timeout: 3)
    )
  }

  @MainActor
  private func scrollDown(_ application: XCUIApplication, times: Int) {
    for _ in 0..<times {
      application.typeKey(.pageDown, modifierFlags: [])
    }
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
      "-uiWindowWidth",
      "1180",
      "-uiWindowHeight",
      "760",
    ]
    application.launchEnvironment["TZ"] = "GMT"
    application.launch()
    return application
  }
}
