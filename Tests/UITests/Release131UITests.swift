import XCTest

/// 1.3.1: settings rows show current values, translation and data settings
/// apply at once, deleting records asks first, and the reading page uses a
/// compact review icon on each block's first line. The API draft page these
/// tests once covered was replaced in 1.3.2; see `Release132UITests`.
final class Release131UITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor private func launch(_ extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--ui-test"] + extra; app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 10))
    }
    @MainActor private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func text(_ element: XCUIElement) -> String {
        element.label + " " + ((element.value as? String) ?? "")
    }
    @MainActor private func flip(_ toggle: XCUIElement) {
        // Tap the switch itself; the row's centre is only its label.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }
    @MainActor private func dismissDialog() {
        let cancel = app.buttons.matching(NSPredicate(format: "label IN {'取消', 'Cancel'}")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3)); cancel.tap()
    }

    @MainActor func testSettingsOverviewShowsCurrentValues() {
        launch(["--fixture-history"])
        app.tabBars.buttons["设置"].tap()
        let basic = app.buttons["basicSettingsLink"]
        XCTAssertTrue(basic.waitForExistence(timeout: 5))
        XCTAssertTrue(text(basic).contains("中文"), text(basic))
        XCTAssertTrue(text(app.buttons["apiSettingsLink"]).contains("自定义 API"), text(app.buttons["apiSettingsLink"]))
        XCTAssertTrue(text(app.buttons["dataSettingsLink"]).contains("3 条"), text(app.buttons["dataSettingsLink"]))
        attach("1.3.1-settings-overview")
        app.buttons["displaySettingsLink"].tap()
        XCTAssertTrue(app.buttons["readerSettingsLink"].waitForExistence(timeout: 5))
        attach("1.3.1-display-settings")
    }

    @MainActor func testSettingsOverviewInDarkAppearance() {
        launch(["--fixture-dark", "--fixture-history"])
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["basicSettingsLink"].waitForExistence(timeout: 5))
        attach("1.3.1-settings-overview-dark")
    }

    @MainActor func testTranslationPreferencesApplyWithoutSaveButton() {
        launch()
        app.tabBars.buttons["设置"].tap(); app.buttons["basicSettingsLink"].tap()
        let target = app.buttons["settingsTargetLanguagePicker"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveSettingsButton"].exists)
        target.tap()
        let options = app.buttons.matching(identifier: "英语")
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 5))
        options.element(boundBy: options.count - 1).tap()
        attach("1.3.1-translation-preferences")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(text(app.buttons["basicSettingsLink"]).contains("英语"), text(app.buttons["basicSettingsLink"]))
    }

    @MainActor func testTurningOffHistoryAsksBeforeDeletingRecords() {
        launch(["--fixture-history"])
        app.tabBars.buttons["设置"].tap(); app.buttons["dataSettingsLink"].tap()
        let toggle = app.switches["saveRecentToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveSettingsButton"].exists)
        attach("1.3.1-data-settings")

        flip(toggle)
        let confirm = app.buttons["关闭并清空"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '3 条'")).firstMatch.exists)
        attach("1.3.1-confirm-disable-history")
        dismissDialog()
        XCTAssertEqual(toggle.value as? String, "1", "Cancelling keeps history on")

        flip(toggle)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(text(app.buttons["dataSettingsLink"]).contains("已关闭"), text(app.buttons["dataSettingsLink"]))
    }

    @MainActor func testReviewIconsSitOnTheFirstLine() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--fixture-image", "--fixture-layout", "--fixture-reader-collapsed"]
        app.launch()
        app.buttons["translateButton"].tap()
        XCTAssertTrue(app.buttons["copyTranslation"].waitForExistence(timeout: 40))
        app.showReadingPresentation()
        let button = app.buttons["reviewTranslationBlock-2"]
        let paragraph = app.descendants(matching: .any)["translationParagraph-2"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.frame.width, 44, accuracy: 0.5)
        XCTAssertEqual(button.frame.height, 44, accuracy: 0.5)
        if paragraph.exists {
            // The icon overlaps the paragraph's first line rather than its middle.
            XCTAssertLessThan(button.frame.minY, paragraph.frame.minY + 8, "\(button.frame) vs \(paragraph.frame)")
        }
        attach("1.3.1-reading-review-icons")
    }
}
