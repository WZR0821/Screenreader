import XCTest

final class Release110UITests: XCTestCase {
    @MainActor func testCameraPasteHiddenPromptCreditAndLanguagePacks() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-test"]; app.launch()
        XCTAssertTrue(app.buttons["takePhoto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pasteInput"].exists)
        XCTAssertFalse(app.buttons["chooseFile"].exists)
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "1.2.0-home"; home.lifetime = .keepAlways; add(home)
        app.buttons["takePhoto"].tap()
        XCTAssertTrue(app.staticTexts["errorBanner"].waitForExistence(timeout: 3))
        app.tabBars.buttons["设置"].tap()
        app.revealForNavigation(app.staticTexts["developerCredit"])
        XCTAssertEqual(app.staticTexts["developerCredit"].label, "Jerry Wong")
        XCTAssertTrue(app.staticTexts["appVersionLabel"].label.contains("1.3.0"))
        let settings = XCTAttachment(screenshot: app.screenshot()); settings.name = "1.2.0-settings"; settings.lifetime = .keepAlways; add(settings)
        app.revealForNavigation(app.buttons["promptSettingsLink"]); app.buttons["promptSettingsLink"].tap()
        app.swipeUp()
        XCTAssertFalse(app.buttons["promptPreview"].exists)
        XCTAssertFalse(app.staticTexts["预览模型指令（英文）"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.revealForNavigation(app.buttons["basicSettingsLink"]); app.buttons["basicSettingsLink"].tap()
        app.buttons["languagePacksLink"].tap()
        XCTAssertTrue(app.staticTexts["languagePackStatus"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["languagePackStatus"].label.contains("请在 iPhone 真机检查"))
        XCTAssertTrue(app.buttons["languagePackTargetPicker"].label.contains("中文"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "1.1.0-language-packs"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testCopyClearAndPasteUsesClipboardText() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-test"]; app.launch()
        let editor = app.textViews["sourceEditor"]
        editor.tap(); editor.typeText("Hello"); app.buttons["完成"].tap()
        let input = XCTAttachment(screenshot: app.screenshot()); input.name = "1.2.1-输入与操作"
        input.lifetime = .keepAlways; add(input)
        app.buttons["translateButton"].tap()
        XCTAssertTrue(app.buttons["copyTranslation"].waitForExistence(timeout: 10))
        let copiedText = app.staticTexts["translationResult"].label
        app.buttons["copyTranslation"].tap()
        XCTAssertEqual(app.buttons["copyTranslation"].value as? String, "已复制")
        app.buttons["editTranslationSource"].tap()
        for _ in 0..<5 where !app.buttons["clearInputButton"].isHittable { app.swipeDown() }
        app.buttons["clearInputButton"].tap()
        app.buttons["pasteInput"].tap()
        let pasted = NSPredicate(format: "value == %@", copiedText)
        expectation(for: pasted, evaluatedWith: editor)
        waitForExpectations(timeout: 5)
        XCTAssertFalse((editor.value as? String ?? "").isEmpty)
    }

    @MainActor func testVerticalReviewShowsOriginalCropAndAppliesConfirmedText() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-test", "--fixture-image", "--fixture-vertical"]; app.launch()
        app.buttons["recognizeOnly"].tap()
        XCTAssertTrue(app.navigationBars["复核不确定文字"].waitForExistence(timeout: 20))
        let first = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'reviewText-'")).firstMatch
        // Multiline TextField is represented as a TextView on some iOS releases.
        XCTAssertTrue(first.exists || app.textViews.matching(NSPredicate(format: "identifier BEGINSWITH 'reviewText-'")).firstMatch.exists)
        let toggles = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH 'confirmReview-'")).firstMatch
        toggles.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggles.value as? String, "1")
        XCTAssertTrue(app.buttons["applyOCRReview"].isEnabled)
        let review = XCTAttachment(screenshot: app.screenshot()); review.name = "1.1.0-ocr-review"; review.lifetime = .keepAlways; add(review)
        app.buttons["applyOCRReview"].tap()
        XCTAssertTrue(app.textViews["sourceEditor"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textViews["sourceEditor"].value as? String ?? "").contains("日本語"))
    }

}
