import XCTest

final class TranslationPolishUITests: XCTestCase {
    @MainActor private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-test"] + extra; app.launch()
        return app
    }
    @MainActor private func translate(_ app: XCUIApplication) {
        let editor = app.textViews["sourceEditor"]
        editor.tap(); editor.typeText("Please translate this short paragraph.")
        app.buttons["完成"].tap()
        reveal(app, app.buttons["translateButton"])
        if app.launchArguments.contains("--fixture-dark") { capture(app, "1.2.1-大字号翻译操作") }
        app.buttons["translateButton"].tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 15))
    }

    @MainActor func testEmptyInputKeepsActionNearbyAndNoReadingButtonsInNavigation() {
        let app = launch()
        XCTAssertFalse(app.buttons["translationReaderSettings"].exists)
        XCTAssertFalse(app.buttons["translationFuriganaToggle"].exists)
        XCTAssertFalse(app.buttons["recentResultButton"].exists)
        XCTAssertTrue(app.navigationBars["翻译"].exists)
        let editor = app.textViews["sourceEditor"], button = app.buttons["translateButton"]
        XCTAssertLessThan(editor.frame.height, 190)
        XCTAssertTrue(app.staticTexts["最近翻译"].exists)
        let panel = app.descendants(matching: .any)["translationInputPanel"]
        for identifier in ["choosePhoto", "takePhoto", "pasteInput", "translateButton"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.minY, panel.frame.minY)
            XCTAssertLessThanOrEqual(control.frame.maxY, panel.frame.maxY)
        }
        XCTAssertFalse(button.isEnabled)
        capture(app, "界面优化-输入页")
        app.tabBars.buttons["设置"].tap()
        capture(app, "1.2.1-原生设置首页")
        app.buttons["displaySettingsLink"].tap(); app.buttons["readerSettingsLink"].tap()
        XCTAssertTrue(app.sliders["readerFontSizeSlider"].exists)
    }

    @MainActor func testChineseResultIsCompactAndDetailsRemainAvailable() {
        let app = launch(); translate(app)
        XCTAssertTrue(app.navigationBars["译文"].exists)
        XCTAssertFalse(app.textViews["sourceEditor"].isHittable)
        XCTAssertFalse(app.buttons["translationReaderSettings"].exists)
        XCTAssertFalse(app.buttons["translationFuriganaToggle"].exists)
        XCTAssertTrue(app.buttons["copyTranslation"].isHittable)
        capture(app, "界面优化-中文译文")
        app.buttons["translationActions"].tap(); app.buttons["showTranslationInformation"].tap()
        XCTAssertTrue(app.navigationBars["翻译信息"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["本次总计"].exists)
        app.navigationBars["翻译信息"].buttons["完成"].tap()
        app.buttons["editTranslationSource"].tap()
        let editor = app.textViews["sourceEditor"]
        XCTAssertTrue(editor.exists); XCTAssertTrue((editor.value as? String ?? "").contains("Please translate"))
        editor.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        let last = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboardResult-' ")).firstMatch
        reveal(app, last); last.tap()
        XCTAssertTrue(app.navigationBars["译文"].exists)
        app.buttons["translationActions"].tap(); app.buttons["retranslateResult"].tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 10))
        app.openTranslationHistory()
        app.buttons["清空"].tap(); app.buttons["清空记录"].tap()
        app.navigationBars["翻译记录"].buttons["完成"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboardResult-' ")).count, 0)
        XCTAssertTrue(app.descendants(matching: .any)["recentTranslationsEmpty"].exists)
    }

    @MainActor func testJapaneseFuriganaBelongsToResultHeader() {
        let app = launch()
        app.buttons["targetLanguagePicker"].tap(); app.buttons["日语"].tap()
        XCTAssertFalse(app.buttons["translationFuriganaToggle"].exists)
        translate(app)
        let toggle = app.buttons["translationFuriganaToggle"]
        let header = app.descendants(matching: .any)["translationResultHeader"]
        XCTAssertTrue(toggle.isHittable)
        XCTAssertGreaterThanOrEqual(toggle.frame.minY, header.frame.minY)
        XCTAssertLessThanOrEqual(toggle.frame.maxY, header.frame.maxY)
        XCTAssertFalse(app.navigationBars["译文"].buttons["translationFuriganaToggle"].exists)
        toggle.tap()
        let result = app.staticTexts["translationResult"]
        expectation(for: NSPredicate(format: "value == '假名注音已开启'"), evaluatedWith: result)
        waitForExpectations(timeout: 8)
        capture(app, "界面优化-日语译文")
    }

    @MainActor func testLongReadingReachesLastParagraphWithoutBottomActionBar() {
        let app = launch(["--fixture-long"]); translate(app)
        XCTAssertFalse(app.buttons["translateButton"].exists)
        let ending = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '全文结束'")).firstMatch
        for _ in 0..<15 where !ending.isHittable { app.swipeUp() }
        XCTAssertTrue(ending.isHittable)
        capture(app, "界面优化-长文末段")
    }

    @MainActor func testDarkLargeTextKeepsInputAndTranslationReachable() {
        let app = launch(["--fixture-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        capture(app, "1.2.1-深色大字输入")
        translate(app)
        XCTAssertTrue(app.staticTexts["translationResult"].isHittable)
        capture(app, "界面优化-深色大字")
    }

    @MainActor func testDashboardHistoryOpensAndReturnsToHome() {
        let app = launch(["--fixture-history"])
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboardResult-'"))
        XCTAssertEqual(rows.count, 2)
        reveal(app, rows.firstMatch)
        capture(app, "界面优化-主页与记录")
        rows.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["译文"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["translationResult"].exists)
        XCTAssertFalse(app.buttons["translationFuriganaToggle"].exists)
        app.navigationBars["译文"].buttons.element(boundBy: 0).tap()
        app.openTranslationHistory()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyRow-' ")).count, 3)
        app.navigationBars["翻译记录"].buttons["完成"].tap()
        XCTAssertFalse(app.buttons["recentResultButton"].exists)
    }

    @MainActor func testChangingTargetInSettingsReturnsToInput() {
        let app = launch(); translate(app)
        app.tabBars.buttons["设置"].tap(); app.buttons["basicSettingsLink"].tap()
        app.buttons["settingsTargetLanguagePicker"].tap(); app.buttons["英语"].tap()
        app.buttons["saveSettingsButton"].tap(); app.tabBars.buttons["翻译"].tap()
        XCTAssertFalse(app.navigationBars["译文"].exists)
        XCTAssertTrue(app.textViews["sourceEditor"].isHittable)
        XCTAssertTrue(app.buttons["targetLanguagePicker"].label.contains("英语"))
    }

    @MainActor func testBackgroundCompletionKeepsHistoryOpenAndResultCanResume() {
        let app = launch(["--fixture-delayed", "--fixture-history"])
        let editor = app.textViews["sourceEditor"]
        editor.tap(); editor.typeText("Please translate this paragraph."); app.buttons["完成"].tap()
        reveal(app, app.buttons["translateButton"]); app.buttons["translateButton"].tap()
        XCTAssertTrue(app.navigationBars["译文"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["translationProgress"].exists)
        capture(app, "构建25-翻译等待")
        app.navigationBars["译文"].buttons.element(boundBy: 0).tap()
        reveal(app, app.buttons["dashboardAllHistory"]); app.buttons["dashboardAllHistory"].tap()
        XCTAssertTrue(app.navigationBars["翻译记录"].waitForExistence(timeout: 3))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyRow-'"))
        expectation(for: NSPredicate { _, _ in rows.count == 4 }, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.navigationBars["翻译记录"].exists, "Finishing a request must not navigate away from history")
        capture(app, "构建25-历史弹窗")
        app.navigationBars["翻译记录"].buttons["完成"].tap()
        let resume = app.buttons["translateButton"]; reveal(app, resume)
        XCTAssertTrue(resume.label.contains("查看译文")); resume.tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["cancelTranslation"].exists)
    }

    @MainActor func testWholeRetranslationFailureKeepsPreviousTextAndOffersRetry() {
        let app = launch(["--fixture-retry-error"]); translate(app)
        let before = app.staticTexts["translationResult"].label
        app.buttons["translationActions"].tap(); app.buttons["retranslateResult"].tap()
        XCTAssertTrue(app.buttons["retryTranslation"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["translationResult"].label, before)
        capture(app, "构建25-重试失败保留译文")
        app.buttons["editTranslationSource"].tap()
        XCTAssertTrue((app.textViews["sourceEditor"].value as? String ?? "").contains("Please translate"))
    }

    @MainActor func testCancelInitialTranslationReturnsToPreservedInput() {
        let app = launch(["--fixture-delayed"])
        let editor = app.textViews["sourceEditor"]
        editor.tap(); editor.typeText("Keep the original input."); app.buttons["完成"].tap()
        reveal(app, app.buttons["translateButton"]); app.buttons["translateButton"].tap()
        XCTAssertTrue(app.buttons["cancelTranslation"].waitForExistence(timeout: 3))
        app.buttons["cancelTranslation"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Keep the original input.")
        XCTAssertFalse(app.navigationBars["译文"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboardResult-' ")).count, 0)
    }

    @MainActor private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<10 where !element.isHittable || element.frame.maxY > app.frame.maxY - 75 {
            if element.exists && element.frame.minY < 110 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
