import XCTest

final class FuriganaUITests: XCTestCase {
    @MainActor func testTranslationSettingsAndHistoryShareOneSwitchWithoutRetranslating() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-test"]
        app.launch()
        let toggle = app.buttons["translationFuriganaToggle"]
        XCTAssertFalse(toggle.exists)
        app.buttons["targetLanguagePicker"].tap(); app.buttons["日语"].tap()
        let editor = app.textViews["sourceEditor"]
        editor.tap(); editor.typeText("Hello, world. This is a translation.")
        app.buttons["完成"].tap()
        app.buttons["translateButton"].tap()
        let result = app.staticTexts["translationResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        let plain = result.label
        XCTAssertTrue(plain.contains("翻訳"))
        toggle.tap()
        expectation(for: NSPredicate(format: "value == '假名注音已开启'"), evaluatedWith: result)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(result.label, plain)
        capture(app, "日语注音-翻译页开启")
        app.tabBars.buttons["设置"].tap()
        app.buttons["displaySettingsLink"].tap()
        app.buttons["readerSettingsLink"].tap()
        let setting = app.switches["readerFuriganaToggle"]
        reveal(app, setting)
        XCTAssertEqual(setting.value as? String, "1")
        setting.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.tabBars.buttons["翻译"].tap()
        XCTAssertEqual(toggle.value as? String, "关闭")
        XCTAssertEqual(result.label, plain)
        XCTAssertNotEqual(result.value as? String, "假名注音已开启")
        let plainHeight = result.frame.height
        app.tabBars.buttons["设置"].tap()
        reveal(app, setting)
        XCTAssertEqual(setting.value as? String, "0")
        setting.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let sizePreset = app.segmentedControls["readerTextSizePicker"]
        reveal(app, sizePreset); sizePreset.buttons["较大"].tap()
        capture(app, "日语注音-设置与预览")
        app.tabBars.buttons["翻译"].tap()
        XCTAssertEqual(toggle.value as? String, "开启")
        expectation(for: NSPredicate(format: "value == '假名注音已开启'"), evaluatedWith: result)
        waitForExpectations(timeout: 10)
        XCTAssertGreaterThan(result.frame.height, plainHeight, "Saved text size applies immediately to the reading page")
        app.navigationBars["译文"].buttons.element(boundBy: 0).tap()
        app.openTranslationHistory()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyRow-'"))
        XCTAssertEqual(rows.count, 1, "Changing a reading preference must not create another translation")
        rows.firstMatch.tap()
        let historyResult = app.scrollViews["recentResultScroll"].staticTexts["translationResult"]
        XCTAssertTrue(historyResult.waitForExistence(timeout: 5))
        XCTAssertEqual(historyResult.label, plain)
        let historyToggle = app.scrollViews["recentResultScroll"].buttons["translationFuriganaToggle"]
        historyToggle.tap()
        XCTAssertEqual(historyToggle.value as? String, "关闭")
        XCTAssertEqual(historyResult.label, plain)
        XCTAssertNotEqual(historyResult.value as? String, "假名注音已开启")
    }

    @MainActor func testJapaneseParagraphListTableAndLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--fixture-furigana"]
        app.launch()
        app.openTranslationHistory()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyRow-' ")).firstMatch.tap()
        let result = app.staticTexts["translationResult"]
        app.buttons["translationFuriganaToggle"].tap()
        expectation(for: NSPredicate(format: "value == '假名注音已开启'"), evaluatedWith: result)
        waitForExpectations(timeout: 10)
        capture(app, "日语注音-段落列表表格")
        let ending = app.staticTexts["translationParagraph-6"]
        reveal(app, ending)
        XCTAssertTrue(ending.label.contains("最後"))
        capture(app, "日语注音-表格与末段")
    }

    @MainActor private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<10 {
            if element.isHittable && element.frame.minY > 110 && element.frame.maxY < app.frame.maxY - 100 { return }
            if element.exists && element.frame.minY < 110 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
