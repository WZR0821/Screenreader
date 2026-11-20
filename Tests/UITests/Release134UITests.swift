import XCTest

/// 1.3.4: 语言优先级. Chinese typed with 自动识别 → 中文 is translated into the
/// next language in the order, and the page says so before and after.
final class Release134UITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor private func launch(_ extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--ui-test"] + extra
        app.launch()
    }

    @MainActor private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor private func type(_ text: String) {
        let editor = app.textViews["sourceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap(); editor.typeText(text)
        if app.keyboards.buttons["完成"].exists { app.keyboards.buttons["完成"].tap() }
        else if app.buttons["完成"].exists { app.buttons["完成"].tap() }
    }

    @MainActor private func openPriority() {
        app.tabBars.buttons["设置"].tap()
        let basic = app.buttons["basicSettingsLink"]
        XCTAssertTrue(basic.waitForExistence(timeout: 5)); basic.tap()
        let link = app.buttons["languagePriorityLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        app.revealForNavigation(link)
    }

    @MainActor func testChineseInputIsShownAndTranslatedIntoTheNextLanguage() {
        launch()
        let source = app.buttons["sourceLanguagePicker"], target = app.buttons["targetLanguagePicker"]
        XCTAssertEqual(source.value as? String, "自动识别"); XCTAssertEqual(target.value as? String, "中文")
        let top = target.frame
        type("这个东西多少钱？")
        // Before anything is sent the page already shows where this text goes.
        XCTAssertEqual(source.value as? String, "中文"); XCTAssertEqual(target.value as? String, "日语")
        XCTAssertTrue(target.label.contains("中文"), "The saved choice is still named: \(target.label)")
        XCTAssertTrue(app.staticTexts["按优先级译为"].exists); XCTAssertTrue(app.staticTexts["自动识别到"].exists)
        XCTAssertEqual(target.frame.height, top.height, accuracy: 0.5, "The hint must not change the one-screen layout")
        attach("1.3.4-输入中文后提示改译为日语")

        target.tap()
        XCTAssertTrue(app.buttons["原文已是中文，按语言优先级译为日语"].waitForExistence(timeout: 5))
        attach("1.3.4-目标语言菜单说明")
        // The menu still marks the saved choice; picking it again changes nothing.
        let options = app.buttons.matching(identifier: "中文")
        options.element(boundBy: options.count - 1).tap()
        XCTAssertEqual(target.value as? String, "日语")

        app.revealForNavigation(app.buttons["translateButton"]); app.buttons["translateButton"].tap()
        let result = app.staticTexts["translationResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        XCTAssertTrue(result.label.contains("こんにちは"), result.label)
        let note = app.staticTexts["targetNote"]
        XCTAssertTrue(note.exists); XCTAssertEqual(note.label, "原文是中文，已按语言优先级改译为日语。")
        attach("1.3.4-改译结果与说明")
        app.buttons["translationActions"].tap(); app.buttons["showTranslationInformation"].tap()
        XCTAssertTrue(app.staticTexts["targetNoteInformation"].waitForExistence(timeout: 5))
        attach("1.3.4-翻译信息里的说明")
    }

    @MainActor func testEnglishInputAndExplicitSourceKeepTheSelectedTarget() {
        launch()
        let source = app.buttons["sourceLanguagePicker"], target = app.buttons["targetLanguagePicker"]
        type("Good morning.")
        XCTAssertEqual(source.value as? String, "自动识别"); XCTAssertEqual(target.value as? String, "中文")
        XCTAssertFalse(app.staticTexts["按优先级译为"].exists)
        // English into English makes no sense either: it follows the same order.
        target.tap()
        var options = app.buttons.matching(identifier: "英语")
        options.element(boundBy: options.count - 1).tap()
        XCTAssertEqual(target.value as? String, "中文"); XCTAssertEqual(source.value as? String, "英语")
        XCTAssertTrue(target.label.contains("英语"))
        attach("1.3.4-英语输入且目标为英语")
        // A source language picked by hand is a decision and is not overridden.
        source.tap()
        options = app.buttons.matching(identifier: "英语")
        options.element(boundBy: options.count - 1).tap()
        XCTAssertEqual(source.value as? String, "英语"); XCTAssertEqual(target.value as? String, "英语")
        XCTAssertFalse(app.staticTexts["按优先级译为"].exists)
    }

    @MainActor func testPriorityCanBeReorderedAndSwitchedOff() {
        launch()
        openPriority()
        let link = app.buttons["languagePriorityLink"]
        XCTAssertTrue(link.label.contains("中文 › 日语 › 英语"), link.label)
        attach("1.3.4-翻译偏好里的语言优先级")
        link.tap()
        XCTAssertTrue(app.navigationBars["语言优先级"].waitForExistence(timeout: 5))
        let toggle = app.switches["smartTargetToggle"]
        XCTAssertEqual(toggle.value as? String, "1", "On by default")
        func row(_ position: Int) -> XCUIElement { app.descendants(matching: .any)["languagePriorityRow-\(position)"].firstMatch }
        func effect(_ code: String) -> XCUIElement { app.descendants(matching: .any)["languagePriorityEffect-\(code)"].firstMatch }
        XCTAssertEqual(row(1).value as? String, "中文"); XCTAssertEqual(row(2).value as? String, "日语")
        XCTAssertEqual(row(3).value as? String, "英语")
        XCTAssertTrue(effect("zh-Hans").label.contains("译为日语"), effect("zh-Hans").label)
        XCTAssertTrue(effect("ja").label.contains("译为中文")); XCTAssertTrue(effect("en").label.contains("译为中文"))
        attach("1.3.4-语言优先级页面")

        // Drag 英语 above 日语 with the system reorder handle.
        let handle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '重新排序' OR label BEGINSWITH 'Reorder'")).element(boundBy: 2)
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.press(forDuration: 0.6, thenDragTo: row(2), withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertEqual(row(1).value as? String, "中文"); XCTAssertEqual(row(2).value as? String, "英语")
        XCTAssertEqual(row(3).value as? String, "日语")
        XCTAssertTrue(effect("zh-Hans").label.contains("译为英语"), effect("zh-Hans").label)
        attach("1.3.4-调整顺序后")
        app.navigationBars["语言优先级"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(link.label.contains("中文 › 英语 › 日语"), link.label)

        // The new order decides where Chinese goes.
        app.tabBars.buttons["翻译"].tap()
        type("这个东西多少钱？")
        XCTAssertEqual(app.buttons["targetLanguagePicker"].value as? String, "英语")
        attach("1.3.4-新顺序下改译为英语")

        // Switched off, the page translates exactly as selected.
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(row(1).waitForExistence(timeout: 1)); XCTAssertFalse(effect("ja").exists)
        attach("1.3.4-关闭自动改译")
        app.navigationBars["语言优先级"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5)); XCTAssertTrue(link.label.contains("关闭"), link.label)
        app.tabBars.buttons["翻译"].tap()
        XCTAssertEqual(app.buttons["targetLanguagePicker"].value as? String, "中文")
        XCTAssertEqual(app.buttons["sourceLanguagePicker"].value as? String, "自动识别")
        XCTAssertFalse(app.staticTexts["按优先级译为"].exists)
    }
}
