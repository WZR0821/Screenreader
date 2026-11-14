import XCTest

/// 1.3.3: a screenshot translation opens as text. 原图直译 is a setting in
/// 基本设置, off by default, and takes effect on the next translation.
final class Release133UITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testQuickScreenshotOpensAsTextUntilImageOverlayIsTurnedOn() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--fixture-image", "--fixture-layout", "--fixture-reader-collapsed"]
        app.launch()
        app.segmentedControls["translationModePicker"].buttons["快速"].tap()
        app.revealForNavigation(app.buttons["translateButton"]); app.buttons["translateButton"].tap()
        XCTAssertTrue(app.buttons["copyTranslation"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.staticTexts["translationResult"].exists)
        XCTAssertFalse(app.segmentedControls["translationPresentationPicker"].exists)
        XCTAssertFalse(app.buttons["imageTranslationBlock-1-0"].exists)
        attach("1.3.3-快速截图直出文字")

        app.tabBars.buttons["设置"].tap(); app.buttons["basicSettingsLink"].tap()
        let toggle = app.switches["imageOverlayToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        app.revealForNavigation(toggle)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        attach("1.3.3-原图直译开关")

        app.tabBars.buttons["翻译"].tap()
        XCTAssertFalse(app.segmentedControls["translationPresentationPicker"].exists,
                       "A result translated as plain text has nothing to place on the image")
        // That result has no positions, but the on-screen OCR does: the main
        // button translates the same screenshot again instead of reopening it.
        app.buttons["editTranslationSource"].tap()
        let translate = app.buttons["translateButton"]
        XCTAssertTrue(translate.waitForExistence(timeout: 5))
        app.revealForNavigation(translate)
        XCTAssertFalse(translate.label.contains("查看译文"), translate.label)
        XCTAssertTrue(translate.label.contains("翻译"), translate.label)
        attach("1.3.3-开关打开后主按钮")
        translate.tap()
        let picker = app.segmentedControls["translationPresentationPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 40))
        XCTAssertTrue(picker.buttons["原图直译"].isSelected)
        XCTAssertEqual(app.buttons["imageTranslationBlock-1-0"].label, "早餐菜单")
        attach("1.3.3-开启后原图直译")
        // The new result has positions, so the button reopens it from now on.
        app.buttons["editTranslationSource"].tap()
        XCTAssertTrue(translate.waitForExistence(timeout: 5))
        XCTAssertTrue(translate.label.contains("查看译文"), translate.label)
    }
}
