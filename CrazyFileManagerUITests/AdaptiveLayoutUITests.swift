import XCTest

final class AdaptiveLayoutUITests: XCTestCase {
  @MainActor
  func
    test_givenTheWindowLaunchesAtTheMinimumSize_whenTheInspectorBecomesAnOverlay_thenEssentialControlsRemainReachable()
  {
    let application = launchApplication(
      scenario: "trashEligible",
      windowWidth: 900,
      windowHeight: 600
    )
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))

    XCTAssertTrue(application.buttons["inspectorOverlayToggle"].waitForExistence(timeout: 3))
    let row = outline.cells["notes.txt"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))

    row.click()
    application.typeKey(.delete, modifierFlags: .command)

    XCTAssertTrue(application.staticTexts["Move to Trash?"].waitForExistence(timeout: 3))
  }

  @MainActor
  func
    test_givenTheWindowLaunchesAtTheDefaultSize_whenResultsAppear_thenTheInspectorStaysInlineWithoutAToggle()
  {
    let application = launchApplication(scenario: "trashEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))

    XCTAssertFalse(application.buttons["inspectorOverlayToggle"].waitForExistence(timeout: 2))
  }

  @MainActor
  private func launchApplication(
    scenario: String = "empty",
    windowWidth: Int = 1_180,
    windowHeight: Int = 760
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
      "\(windowWidth)",
      "-uiWindowHeight",
      "\(windowHeight)",
    ]
    application.launchEnvironment["TZ"] = "GMT"
    application.launch()
    return application
  }
}
