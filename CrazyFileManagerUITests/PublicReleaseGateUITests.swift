import XCTest

final class PublicReleaseGateUITests: XCTestCase {
  @MainActor
  func
    test_givenThePublicReleaseGateIsSimulated_whenAnOtherwiseNormalItemIsSelected_thenRenameAndTrashAreDisabledWithAnHonestReason()
  {
    let application = launchApplication(scenario: "trashEligible", simulateReleaseGate: true)
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    let row = outline.cells["notes.txt"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))

    row.click()

    let explanation = application.staticTexts["inspectorRestrictionExplanation"]
    XCTAssertTrue(explanation.waitForExistence(timeout: 3))
    XCTAssertEqual(
      explanation.value as? String,
      "Rename is temporarily disabled in this release pending independent security review."
    )
    XCTAssertFalse(application.textFields["renameField"].exists)
    application.typeKey(.delete, modifierFlags: .command)
    XCTAssertFalse(application.staticTexts["Move to Trash?"].waitForExistence(timeout: 2))
  }

  @MainActor
  func
    test_givenThePublicReleaseGateIsNotSimulated_whenAnOtherwiseNormalItemIsSelected_thenRenameAndTrashRemainAvailable()
  {
    let application = launchApplication(scenario: "trashEligible", simulateReleaseGate: false)
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    let row = outline.cells["notes.txt"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))

    row.click()

    XCTAssertFalse(application.staticTexts["inspectorRestrictionExplanation"].exists)
    application.typeKey(.delete, modifierFlags: .command)
    XCTAssertTrue(application.staticTexts["Move to Trash?"].waitForExistence(timeout: 3))
  }

  @MainActor
  private func launchApplication(
    scenario: String = "empty",
    simulateReleaseGate: Bool = false
  ) -> XCUIApplication {
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
    if simulateReleaseGate {
      application.launchArguments += ["-uiSimulatePublicReleaseGate"]
    }
    application.launchEnvironment["TZ"] = "GMT"
    application.launch()
    return application
  }
}
