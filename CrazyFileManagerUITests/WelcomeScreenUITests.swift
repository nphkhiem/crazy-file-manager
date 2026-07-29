import XCTest

final class WelcomeScreenUITests: XCTestCase {
  @MainActor
  func test_givenApplicationIsNotRunning_whenApplicationLaunches_thenShowsTrustFirstWelcome() {
    let application = XCUIApplication()
    application.launch()

    XCTAssertTrue(
      application.staticTexts["Find what is using your storage"].waitForExistence(timeout: 3)
    )
  }

  @MainActor
  func test_givenApplicationIsNotRunning_whenApplicationLaunches_thenExposesHomeFolderScope() {
    let application = XCUIApplication()
    application.launch()

    XCTAssertTrue(application.staticTexts["Home Folder"].waitForExistence(timeout: 3))
  }
}
