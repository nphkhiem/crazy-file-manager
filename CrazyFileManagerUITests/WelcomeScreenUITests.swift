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
