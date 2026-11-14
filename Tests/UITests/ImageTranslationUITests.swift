import XCTest

final class ImageTranslationUITests: XCTestCase {
    @MainActor private func launch(_ extra: [String] = [], quick: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        // 原图直译 is off by default since 1.3.3; these tests cover the module itself.
        app.launchArguments = ["--ui-test", "--fixture-image", "--fixture-layout", "--fixture-reader-collapsed", "--fixture-image-overlay"] + extra
        app.launch()
        if quick { app.segmentedControls["translationModePicker"].buttons["快速"].tap() }
        if extra.contains("--fixture-vertical") {
            app.revealForNavigation(app.segmentedControls["textDirectionPicker"])
            app.segmentedControls["textDirectionPicker"].buttons["竖排日语"].tap()
        }
        app.revealForNavigation(app.buttons["translateButton"]); app.buttons["translateButton"].tap()
        XCTAssertTrue(app.segmentedControls["translationPresentationPicker"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.buttons["imageTranslationBlock-1-0"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testQuickImageDefaultsToOverlayAndSwitchesToReadingAndOriginal() {
        let app = launch(quick: true)
        let picker = app.segmentedControls["translationPresentationPicker"]
        XCTAssertTrue(picker.buttons["原图直译"].isSelected)
        XCTAssertEqual(app.buttons["imageTranslationBlock-1-0"].label, "早餐菜单")
        capture(app, "1.3.0-原图直译")
        app.buttons["imageOriginalToggle"].tap()
        capture(app, "1.3.0-原图对照")
        XCTAssertEqual(app.buttons["imageOriginalToggle"].value as? String, "原图")
        XCTAssertFalse(app.buttons["imageTranslationBlock-1-0"].exists)
        app.buttons["imageOriginalToggle"].tap()
        picker.buttons["阅读"].tap()
        XCTAssertEqual(app.staticTexts["translationResult"].label, "早餐菜单")
        XCTAssertTrue(app.buttons["copyTranslation"].exists)
        capture(app, "1.3.0-阅读模式")
        picker.buttons["原图直译"].tap()
        app.buttons["imageTranslationBlock-1-0"].tap()
        XCTAssertTrue(app.navigationBars["核对译文"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["translationReviewCrop"].waitForExistence(timeout: 5))
        capture(app, "1.3.0-点按核对")
        app.buttons["closeTranslationReview"].tap()
        XCTAssertTrue(picker.buttons["原图直译"].isSelected)
        app.buttons["editTranslationSource"].tap()
        app.revealForNavigation(app.buttons["clearInputButton"]); app.buttons["clearInputButton"].tap()
        XCTAssertFalse(app.segmentedControls["translationPresentationPicker"].exists)
    }

    @MainActor func testTableCellsRemainSeparateAndZoomCanOpenReview() {
        let app = launch(["--fixture-review-table"])
        XCTAssertTrue(app.buttons["imageTranslationBlock-2-0"].exists)
        XCTAssertTrue(app.buttons["imageTranslationBlock-2-2"].exists)
        capture(app, "1.3.0-表格对齐")
        app.buttons["expandImageTranslation"].tap()
        XCTAssertTrue(app.navigationBars["原图直译"].waitForExistence(timeout: 5))
        let zoom = app.scrollViews["imageTranslationZoom"]
        zoom.pinch(withScale: 2, velocity: 1)
        zoom.doubleTap()
        app.buttons["zoomOriginalToggle"].tap()
        capture(app, "1.3.0-放大原图对照")
        XCTAssertFalse(app.buttons["imageTranslationBlock-1-0"].exists)
        app.buttons["zoomOriginalToggle"].tap()
        capture(app, "1.3.0-放大查看")
        zoom.buttons["imageTranslationBlock-2-2"].tap()
        XCTAssertTrue(app.navigationBars["核对译文"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["translationReviewSource-2"].exists)
        app.buttons["closeTranslationReview"].tap()
        XCTAssertTrue(app.navigationBars["译文"].exists)
    }

    @MainActor func testDarkLargeTextKeepsOverlayControlsAndReadingReachable() {
        let app = launch(["--fixture-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        capture(app, "1.3.0-深色大字号")
        app.segmentedControls["translationPresentationPicker"].buttons["阅读"].tap()
        XCTAssertTrue(app.staticTexts["translationResult"].exists)
        app.buttons["editTranslationSource"].tap()
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["displaySettingsLink"].exists)
    }

    @MainActor func testVerticalJapaneseRetainsRightToLeftColumns() {
        let app = launch(["--fixture-vertical"])
        let first = app.buttons["imageTranslationBlock-1-0"], second = app.buttons["imageTranslationBlock-2-0"]
        app.revealForNavigation(first)
        XCTAssertTrue(first.label.contains("竖排")); XCTAssertGreaterThan(first.frame.minX, second.frame.minX)
        XCTAssertGreaterThan(first.frame.height, first.frame.width * 3)
        capture(app, "1.3.0-竖排原图直译")
        first.tap()
        XCTAssertTrue(app.navigationBars["核对译文"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["translationReviewCrop"].waitForExistence(timeout: 5))
    }
}
