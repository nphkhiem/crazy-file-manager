import XCTest

final class WelcomeScreenUITests: XCTestCase {
  @MainActor
  func testFreshLaunchShowsTrustFirstWelcome() {
    let application = XCUIApplication()
    application.launch()

    XCTAssertTrue(
      application.staticTexts["Find what is using your storage"].waitForExistence(timeout: 3)
    )
  }

  @MainActor
  func testFreshLaunchExposesHomeFolderScope() {
    let application = XCUIApplication()
    application.launch()

    XCTAssertTrue(application.staticTexts["Home Folder"].waitForExistence(timeout: 3))
  }
}
