import XCTest

final class SettingsUITests: XCTestCase {
  @MainActor
  func test_givenTheAppIsRunning_whenSettingsOpens_thenAllFourTabsAreShown() {
    let application = launchApplication()

    application.typeKey(",", modifierFlags: .command)

    XCTAssertTrue(application.buttons["Scan Data"].waitForExistence(timeout: 3))
    XCTAssertTrue(application.buttons["Update Checks"].exists)
    XCTAssertTrue(application.buttons["Privacy"].exists)
    XCTAssertTrue(application.buttons["About"].exists)
  }

  @MainActor
  func test_givenCachedResultsScenario_whenScanDataTabIsShown_thenSizeScopeAndExpiryAppear() {
    let application = launchApplication(scenario: "cachedResults")

    application.typeKey(",", modifierFlags: .command)
    application.buttons["Scan Data"].click()

    XCTAssertTrue(application.staticTexts["2.4 MB"].waitForExistence(timeout: 3))
    XCTAssertTrue(application.buttons["settingsClearScanDataButton"].exists)
  }

  @MainActor
  func test_givenCachedResultsScenario_whenClearScanDataIsClicked_thenSizeUpdatesToNoSavedData() {
    let application = launchApplication(scenario: "cachedResults")

    application.typeKey(",", modifierFlags: .command)
    application.buttons["Scan Data"].click()
    XCTAssertTrue(application.staticTexts["2.4 MB"].waitForExistence(timeout: 3))

    application.buttons["settingsClearScanDataButton"].click()

    XCTAssertTrue(application.staticTexts["No saved scan data"].waitForExistence(timeout: 3))
  }

  @MainActor
  func test_givenTheToggleIsEnabled_whenTheAppRelaunches_thenTheToggleStaysEnabled() {
    let firstLaunch = launchApplication()
    firstLaunch.typeKey(",", modifierFlags: .command)
    firstLaunch.buttons["Update Checks"].click()
    let toggle = firstLaunch.checkBoxes["automaticUpdateCheckToggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 3))
    if toggle.value as? Int == 0 {
      toggle.click()
    }
    XCTAssertEqual(toggle.value as? Int, 1)
    firstLaunch.terminate()

    let secondLaunch = launchApplication()
    secondLaunch.typeKey(",", modifierFlags: .command)
    secondLaunch.buttons["Update Checks"].click()
    let reopenedToggle = secondLaunch.checkBoxes["automaticUpdateCheckToggle"]
    XCTAssertTrue(reopenedToggle.waitForExistence(timeout: 3))
    XCTAssertEqual(reopenedToggle.value as? Int, 1)

    if reopenedToggle.value as? Int == 1 {
      reopenedToggle.click()
    }
  }

  @MainActor
  func test_givenAnAvailableUpdate_whenCheckForUpdatesIsClicked_thenTheConfirmationDialogShows() {
    let application = launchApplication()

    application.typeKey(",", modifierFlags: .command)
    application.buttons["Update Checks"].click()
    application.buttons["checkForUpdatesButton"].click()
    XCTAssertTrue(application.buttons["downloadUpdateButton"].waitForExistence(timeout: 3))

    application.buttons["downloadUpdateButton"].click()

    XCTAssertTrue(application.sheets.buttons["Download"].waitForExistence(timeout: 3))
    application.sheets.buttons["Cancel"].click()
  }

  @MainActor
  func test_givenSettingsIsOpen_whenPrivacyTabIsShown_thenItStatesMetadataOnlyLocalScanning() {
    let application = launchApplication()

    application.typeKey(",", modifierFlags: .command)
    application.buttons["Privacy"].click()

    XCTAssertTrue(
      application.staticTexts.matching(
        NSPredicate(format: "value CONTAINS[c] %@", "metadata")
      ).firstMatch.waitForExistence(timeout: 3)
    )
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
