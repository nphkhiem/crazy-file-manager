import XCTest

final class VoiceOverLabelingUITests: XCTestCase {
  @MainActor
  func
    test_givenASelectedItem_whenTheInspectorShowsDetailRows_thenEachRowExposesACombinedLabelAndValue()
  {
    let application = launchApplication(scenario: "trashEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    let row = outline.cells["notes.txt"]
    XCTAssertTrue(row.waitForExistence(timeout: 3))

    row.click()

    let typeRow = application.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "Type: File"))
      .firstMatch
    XCTAssertTrue(typeRow.waitForExistence(timeout: 3))
    XCTAssertFalse(application.staticTexts["Type"].exists)
  }

  @MainActor
  func
    test_givenTheAllItemsSearchFieldHasText_whenInspected_thenItStillExposesARealAccessibilityLabel()
  {
    let application = launchApplication(scenario: "allItemsEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    application.radioButtons["All Items"].click()
    let searchField = application.textFields["allItemsSearchField"]
    XCTAssertTrue(searchField.waitForExistence(timeout: 3))
    XCTAssertEqual(searchField.label, "Search names and paths")

    searchField.click()
    searchField.typeText("cloud")

    XCTAssertEqual(searchField.label, "Search names and paths")
  }

  @MainActor
  func
    test_givenTheAllItemsFiltersPopoverIsOpen_whenInspected_thenEachControlExposesARealAccessibilityLabel()
  {
    let application = launchApplication(scenario: "allItemsEligible")
    let outline = application.outlines["storageTreeOutline"]
    XCTAssertTrue(outline.waitForExistence(timeout: 3))
    application.radioButtons["All Items"].click()
    let filtersButton = application.buttons["allItemsFiltersButton"]
    XCTAssertTrue(filtersButton.waitForExistence(timeout: 3))

    filtersButton.click()

    let popover = application.popovers.firstMatch
    XCTAssertTrue(popover.waitForExistence(timeout: 3))
    let filesToggle = popover.checkBoxes["allItemsKindFilterFiles"]
    XCTAssertTrue(filesToggle.waitForExistence(timeout: 3))
    XCTAssertEqual(filesToggle.label, "Files")
    let hiddenPicker = popover.popUpButtons["allItemsHiddenFilter"]
    XCTAssertTrue(hiddenPicker.exists)
    XCTAssertEqual(hiddenPicker.label, "Hidden")
    let cloudPicker = popover.popUpButtons["allItemsCloudOnlyFilter"]
    XCTAssertTrue(cloudPicker.exists)
    XCTAssertEqual(cloudPicker.label, "Cloud")
    let diskUsedField = popover.textFields["allItemsMinimumDiskUsedField"]
    XCTAssertTrue(diskUsedField.exists)
    XCTAssertEqual(diskUsedField.label, "Minimum Disk Used")
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
