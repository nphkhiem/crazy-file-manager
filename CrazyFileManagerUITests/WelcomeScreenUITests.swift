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
  private func launchApplication() -> XCUIApplication {
    let application = XCUIApplication()
    application.terminate()
    application.launchArguments = [
      "-ApplePersistenceIgnoreState",
      "YES",
    ]
    application.launch()
    return application
  }
}
