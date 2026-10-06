import XCTest

final class ScreenreaderUXTests: XCTestCase {
    private var app: XCUIApplication!
    @MainActor private func launch() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--ui-test"]; app.launch()
    }
    @MainActor func testSettingsOverviewFillsOneScreenWithoutScrolling() {
        launch(); app.tabBars.buttons["设置"].tap()
        let ids = ["basicSettingsLink", "apiSettingsLink", "promptSettingsLink", "displaySettingsLink", "dataSettingsLink", "fullScreenShortcutLink", "usageGuideLink"]
        XCTAssertTrue(app.buttons[ids[0]].waitForExistence(timeout: 5))
        for id in ids { XCTAssertTrue(app.buttons[id].isHittable, "\(id) must be visible without scrolling") }
        XCTAssertTrue(app.staticTexts["developerCredit"].isHittable)
        XCTAssertFalse(app.scrollViews["settingsAccessibleScroll"].exists)
        let before = app.buttons["usageGuideLink"].frame
        app.swipeUp()
        XCTAssertEqual(app.buttons["usageGuideLink"].frame, before, "Standard settings overview should not scroll")
        attach("Screenreader-settings-one-screen")
    }

    @MainActor func testThreePromptDraftsSaveSeparatelyAndResetOnlySelectedMode() {
        launch(); app.tabBars.buttons["设置"].tap(); app.buttons["promptSettingsLink"].tap()
        let picker = app.segmentedControls["promptModePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let expected = ["快速": "Brief labels.", "专业": "Keep tables.", "识图": "Describe visible objects."]
        for mode in ["快速", "专业", "识图"] {
            picker.buttons[mode].tap()
            let editor = app.textViews["customPromptEditor"]
            XCTAssertEqual(editor.value as? String, "")
            editor.tap()
            // Send words separately so the simulator keyboard settles between
            // events; assert the actual input before testing persistence.
            let words = expected[mode]!.split(separator: " ")
            for (index, word) in words.enumerated() { editor.typeText(String(word) + (index < words.count - 1 ? " " : "")) }
            XCTAssertEqual(editor.value as? String, expected[mode])
            app.buttons["完成"].tap()
        }
        app.buttons["savePromptButton"].tap()
        XCTAssertTrue(app.staticTexts["promptSavedNotice"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap(); app.buttons["promptSettingsLink"].tap()
        for mode in ["快速", "专业", "识图"] {
            picker.buttons[mode].tap()
            XCTAssertEqual(app.textViews["customPromptEditor"].value as? String, expected[mode])
        }
        picker.buttons["专业"].tap(); app.buttons["resetPromptButton"].tap()
        app.buttons["savePromptButton"].tap()
        picker.buttons["快速"].tap()
        XCTAssertEqual(app.textViews["customPromptEditor"].value as? String, expected["快速"])
        picker.buttons["识图"].tap()
        XCTAssertEqual(app.textViews["customPromptEditor"].value as? String, expected["识图"])
        attach("Screenreader-independent-mode-prompts")
    }

    @MainActor func testRapidLanguageSwapsKeepThePairConsistent() {
        launch()
        app.buttons["sourceLanguagePicker"].tap(); app.buttons["英语"].tap()
        app.buttons["targetLanguagePicker"].tap(); app.buttons["日语"].tap()
        for _ in 0..<5 { app.buttons["swapLanguagesButton"].tap() }
        XCTAssertEqual(app.buttons["sourceLanguagePicker"].value as? String, "日语")
        XCTAssertEqual(app.buttons["targetLanguagePicker"].value as? String, "英语")
        app.tabBars.buttons["设置"].tap(); app.buttons["basicSettingsLink"].tap()
        XCTAssertTrue(app.buttons["settingsSourceLanguagePicker"].label.contains("日语"))
        XCTAssertTrue(app.buttons["settingsTargetLanguagePicker"].label.contains("英语"))
        attach("Screenreader-swap-languages")
    }

    @MainActor func testDataPreferencesSaveWithoutChangingLanguageOrProvider() {
        launch(); app.tabBars.buttons["设置"].tap(); app.buttons["dataSettingsLink"].tap()
        let keep = app.buttons["historyLimitPicker"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5)); keep.tap(); app.buttons["100 条"].tap()
        app.buttons["saveSettingsButton"].tap()
        XCTAssertTrue(app.staticTexts["settingsNotice"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap(); app.buttons["dataSettingsLink"].tap()
        XCTAssertTrue(app.buttons["historyLimitPicker"].label.contains("100"))
        app.navigationBars.buttons.firstMatch.tap(); app.buttons["apiSettingsLink"].tap()
        XCTAssertTrue(app.buttons["providerPicker"].label.contains("自定义 API"))
        attach("Screenreader-data-preferences")
    }

    @MainActor func testFreshInstallUsesChineseUIEnglishTargetAndDeepSeek() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--ui-test", "--fixture-defaults"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["翻译"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["targetLanguagePicker"].value as? String, "英语")
        XCTAssertEqual(app.buttons["sourceLanguagePicker"].value as? String, "自动识别")
        attach("build17-Chinese-home-English-target")
        app.tabBars.buttons["设置"].tap()
        app.buttons["apiSettingsLink"].tap()
        XCTAssertTrue(app.buttons["providerPicker"].label.contains("DeepSeek"))
        XCTAssertTrue(app.buttons["chooseModelButton"].label.contains("deepseek-flash"))
        attach("build17-default-DeepSeek")
    }

    @MainActor private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
