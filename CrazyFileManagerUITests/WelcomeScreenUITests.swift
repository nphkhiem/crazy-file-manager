import XCTest

final class WelcomeScreenUITests: XCTestCase {
  @MainActor
  func test_givenApplicationIsNotRunning_whenApplicationLaunches_thenShowsTrustFirstWelcome() {
    let application = launchApplication()

    XCTAssertTrue(
      application.staticTexts["Find what is using your storage"].waitForExistence(timeout: 3)
    )
  }

  @MainActor
  func test_givenApplicationIsNotRunning_whenApplicationLaunches_thenExposesHomeFolderScope() {
    let application = launchApplication()

    XCTAssertTrue(application.staticTexts["Home Folder"].waitForExistence(timeout: 3))
  }

  @MainActor
  func test_givenApplicationHasNotScanned_whenWelcomeAppears_thenExposesExplicitScanButton() {
    let application = launchApplication()

    XCTAssertTrue(application.buttons["scanButton"].waitForExistence(timeout: 3))
    XCTAssertEqual(application.buttons["scanButton"].label, "Scan Home Folder")
  }

  @MainActor
  func
    test_givenWelcomeAppears_whenScopeChoicesAreInspected_thenAllChoicesAndHomeDefaultAreAccessible()
  {
    let application = launchApplication()
    let home = application.buttons["homeFolderScopeButton"]

    XCTAssertTrue(home.waitForExistence(timeout: 3))
    XCTAssertTrue(application.buttons["entireDiskScopeButton"].exists)
    XCTAssertTrue(application.buttons["customScopeButton"].exists)
    XCTAssertEqual(home.value as? String, "Selected")
  }

  @MainActor
  func test_givenEntireDiskIsChosen_whenGuidanceAppears_thenItIsNonBlockingAndDismissible() {
    let application = launchApplication()
    let entireDisk = application.buttons["entireDiskScopeButton"]
    XCTAssertTrue(entireDisk.waitForExistence(timeout: 3))

    entireDisk.click()

    XCTAssertTrue(
      application.staticTexts["Full Disk Access is optional"]
        .waitForExistence(timeout: 3)
    )
    XCTAssertTrue(application.buttons["Open System Settings"].exists)
    XCTAssertEqual(
      application.buttons["scanButton"].label,
      "Scan Entire Internal Disk"
    )
    application.buttons["Not Now"].click()
    XCTAssertFalse(
      application.staticTexts["Full Disk Access is optional"].exists
    )
  }

  @MainActor
  func
    test_givenCachedResultsScenario_whenApplicationLaunches_thenItShowsSavedScopeTimestampAndActions()
  {
    let application = launchApplication(scenario: "cachedResults")

    XCTAssertTrue(
      application.staticTexts["Saved scan results"].waitForExistence(timeout: 3)
    )
    let detail = application.staticTexts["cacheStatusDetail"]
    XCTAssertTrue(detail.exists)
    let detailValue = detail.value as? String ?? ""
    XCTAssertTrue(detailValue.contains("Home Folder"))
    XCTAssertTrue(detailValue.contains("Aug 1, 2026 at 10:00 AM"))
    XCTAssertTrue(application.buttons["scanPrimaryButton"].exists)
    XCTAssertEqual(application.buttons["scanPrimaryButton"].label, "Rescan")
    XCTAssertTrue(application.buttons["clearScanDataButton"].exists)
    XCTAssertTrue(application.buttons["clearScanDataButton"].isEnabled)
  }

  @MainActor
  func
    test_givenCachedResultsScenario_whenClearScanDataFails_thenPathFreeNoticeAppearsWithoutHidingSavedMetadata()
  {
    let application = launchApplication(scenario: "cachedResultsClearFailure")
    let savedResults = application.staticTexts["Saved scan results"]
    XCTAssertTrue(savedResults.waitForExistence(timeout: 3))
    let detail = application.staticTexts["cacheStatusDetail"]
    XCTAssertTrue(detail.exists)

    application.buttons["clearScanDataButton"].click()

    XCTAssertTrue(
      application.staticTexts["Saved scan data needs attention"]
        .waitForExistence(timeout: 3)
    )
    XCTAssertTrue(
      application.staticTexts[
        "Saved scan data couldn’t be removed. Quit and reopen the app."
      ].exists
    )
    XCTAssertTrue(savedResults.exists)
    XCTAssertTrue((detail.value as? String ?? "").contains("Aug 1, 2026 at 10:00 AM"))
  }

  @MainActor
  func
    test_givenExpiredResultsScenario_whenApplicationLaunches_thenItExplainsExpiryAndOffersScanAgain()
  {
    let application = launchApplication(scenario: "expiredResults")

    XCTAssertTrue(
      application.staticTexts["Saved scan results expired"]
        .waitForExistence(timeout: 3)
    )
    XCTAssertTrue(
      application.staticTexts[
        "Saved scan results have expired. Scan again to refresh them."
      ].exists
    )
    XCTAssertTrue(application.buttons["scanButton"].exists)
    XCTAssertEqual(application.buttons["scanButton"].label, "Scan Again")
  }

  @MainActor
  func
    test_givenRenameEligibleScenario_whenTheEligibleRowIsSelected_thenAFocusedInspectorRenameControlAppears()
  {
    let application = launchApplication(scenario: "cachedResultsRenameEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    let row = outline.cells["notes.txt"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))

    row.click()

    XCTAssertTrue(application.buttons["inspectorRenameButton"].waitForExistence(timeout: 3))
  }

  @MainActor
  func
    test_givenRenameEligibleScenario_whenTheEligibleRowIsDoubleClicked_thenInlineEditingBeginsWithoutMutating()
  {
    let application = launchApplication(scenario: "cachedResultsRenameEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 10))
    let row = outline.cells["notes.txt"]
    XCTAssertTrue(row.waitForExistence(timeout: 10))

    row.doubleClick()

    XCTAssertTrue(application.textFields["renameField"].waitForExistence(timeout: 10))
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
