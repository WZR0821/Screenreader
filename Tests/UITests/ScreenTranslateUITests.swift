import XCTest

final class ScreenTranslateUITests: XCTestCase {
    var app: XCUIApplication!
    @MainActor private func launch(error: Bool = false, extra: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-test"] + (error ? ["--fixture-error"] : []) + extra
        app.launch()
    }
    @MainActor private func translate(_ text: String) {
        let editor = app.textViews["sourceEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        if !editor.isHittable { app.swipeUp() }
        editor.tap(); editor.typeText(text)
        if app.keyboards.buttons["完成"].exists { app.keyboards.buttons["完成"].tap() }
        else if app.buttons["完成"].exists { app.buttons["完成"].tap() }
        app.swipeUp()
        let button = app.buttons["translateButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
    }
    @MainActor func testTextTranslationShowsResultAndRecentResult() {
        launch()
        translate("Hello, world!")
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["translationResult"].label.contains("你好"))
        XCTAssertTrue(app.staticTexts["translationResult"].isHittable, "Translation should scroll into view automatically")
        attach("译文界面")
        app.buttons["recentResultButton"].tap()
        XCTAssertTrue(app.navigationBars["翻译记录"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyRow-'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["translationResult"].exists)
    }

    @MainActor func testProfessionalScreenshotHasTypedLayoutAndRepeatsFromCache() {
        launch(extra: ["--fixture-image", "--fixture-layout"])
        app.buttons["translateButton"].tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 25))
        XCTAssertEqual(app.staticTexts["translationResult"].label, "早餐菜单")
        XCTAssertTrue(app.staticTexts["说明"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "450")).firstMatch.exists)
        attach("专业排版首屏-1.8")
        let last = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "加入购物车")).firstMatch
        for _ in 0..<10 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isHittable)
        attach("专业排版末段-1.8")
        app.buttons["translateButton"].tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 10))
        let cache = app.staticTexts["复用译文"]
        for _ in 0..<10 where !cache.isHittable { app.swipeUp() }
        XCTAssertTrue(cache.exists)
        attach("缓存复用-1.8")
    }

    @MainActor func testJapaneseMenuShowsItemPricesConditionsAndLastButton() {
        launch(extra: ["--fixture-image", "--fixture-japanese"])
        app.buttons["translateButton"].tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts["translationResult"].label, "午餐菜单")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "不加酱汁")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "450日元")).firstMatch.exists)
        attach("日语菜单App首屏-1.9")
        let last = app.staticTexts["加入购物车"]
        for _ in 0..<8 where !last.isHittable { app.swipeUp() }
        XCTAssertTrue(last.isHittable)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "优惠券不可叠加")).firstMatch.exists)
        attach("日语菜单App末段-1.9")
    }

    @MainActor func testJapaneseVisualMenuHasSectionsAndReadableOriginal() {
        launch(extra: ["--fixture-image", "--fixture-japanese"])
        app.segmentedControls["translationModePicker"].buttons["识图"].tap()
        app.buttons["translateButton"].tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts["translationResult"].label, "文字大意")
        attach("日语识图App首屏-1.9")
        let heading = app.staticTexts["画面大意"]
        for _ in 0..<8 where !heading.isHittable { app.swipeUp() }
        XCTAssertTrue(heading.isHittable)
        let original = app.buttons["查看原文"]
        for _ in 0..<5 where !original.isHittable { app.swipeUp() }
        XCTAssertTrue(original.isHittable); original.tap()
        let source = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ランチメニュー")).firstMatch
        for _ in 0..<8 where !source.isHittable { app.swipeUp() }
        XCTAssertTrue(source.exists)
        attach("日语识图原文-1.9")
    }

    @MainActor func testUncertainOCRCanRetryInVisualMode() {
        launch(extra: ["--fixture-image", "--fixture-uncertain"])
        app.buttons["translateButton"].tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 20))
        let retry = app.buttons["retryVisualMode"]
        for _ in 0..<8 where !retry.isHittable { app.swipeUp() }
        XCTAssertTrue(retry.isHittable); attach("低置信度重试入口-1.8")
        retry.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "蓝色杯子")).firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.textViews["sourceEditor"].exists)
        XCTAssertTrue(app.segmentedControls["translationModePicker"].buttons["识图"].isSelected)
        attach("识图重试结果-1.8")
    }
    @MainActor func testAuthenticationFailureIsVisibleAndRetryRemainsAvailable() {
        launch(error: true)
        translate("Hello!")
        XCTAssertTrue(app.otherElements["errorBanner"].waitForExistence(timeout: 10) || app.staticTexts.containing(NSPredicate(format: "label CONTAINS '401'")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["translateButton"].exists)
        attach("接口错误提示")
    }
    @MainActor func testSettingsSaveAndAPIFieldsAreAvailable() {
        launch()
        app.tabBars.buttons["设置"].tap()
        openSettings("apiSettingsLink")
        XCTAssertTrue(app.secureTextFields["apiKeyField"].exists)
        XCTAssertTrue(app.textFields["modelField"].exists)
        app.buttons["fetchModelsButton"].tap()
        XCTAssertTrue(app.navigationBars["选择模型"].waitForExistence(timeout: 5))
        app.buttons["ui-test-model"].tap()
        app.buttons["testConnectionButton"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '连接成功'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["saveSettingsButton"].tap()
        XCTAssertTrue(app.staticTexts["settingsNotice"].waitForExistence(timeout: 5) || app.staticTexts.containing(NSPredicate(format: "label CONTAINS '设置已保存'")).firstMatch.exists)
        attach("设置界面")
        for _ in 0..<4 where !app.textFields["apiURLField"].exists { app.swipeUp() }
        XCTAssertTrue(app.textFields["apiURLField"].waitForExistence(timeout: 5))
    }

    @MainActor func testSettingsOverviewHasDeveloperAndUsageInstructions() {
        launch()
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["basicSettingsLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["apiSettingsLink"].exists)
        for _ in 0..<3 where !app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'WANG ZIRUI'")).firstMatch.isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'WANG ZIRUI'")).firstMatch.exists)
        attach("新版设置总览")
        openSettings("usageGuideLink")
        XCTAssertTrue(app.navigationBars["使用说明"].waitForExistence(timeout: 5))
        for _ in 0..<3 where !app.buttons["actionButtonInstructionsLink"].isHittable { app.swipeUp() }
        app.buttons["actionButtonInstructionsLink"].tap()
        XCTAssertTrue(app.navigationBars["操作按钮"].waitForExistence(timeout: 5))
        attach("操作按钮教程首页")
        for _ in 0..<5 { app.swipeUp() }
        attach("操作按钮教程后半部分")
        for _ in 0..<8 where !app.buttons["openShortcutsFromGuide"].isHittable { app.swipeDown() }
        app.buttons["openShortcutsFromGuide"].tap()
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.shortcuts").wait(for: .runningForeground, timeout: 10))
    }

    @MainActor func testLanguageSelectionTranslationAndSettingsRemainConsistent() {
        launch()
        XCTAssertFalse(app.buttons["swapLanguagesButton"].isEnabled)
        selectLanguage("sourceLanguagePicker", title: "英语")
        selectLanguage("targetLanguagePicker", title: "日语")
        XCTAssertTrue(app.buttons["swapLanguagesButton"].isEnabled)
        attach("中英日语言选择")
        translate("Hello, world!")
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["translationResult"].label.contains("こんにちは"))
        attach("英语翻译日语")
        app.tabBars.buttons["设置"].tap()
        openSettings("apiSettingsLink")
        app.buttons["saveSettingsButton"].tap()
        app.navigationBars.buttons["设置"].tap()
        openSettings("basicSettingsLink")
        XCTAssertTrue(app.buttons["settingsSourceLanguagePicker"].label.contains("英语"))
        XCTAssertTrue(app.buttons["settingsTargetLanguagePicker"].label.contains("日语"))
        selectLanguage("settingsSourceLanguagePicker", title: "日语")
        selectLanguage("settingsTargetLanguagePicker", title: "英语")
        app.buttons["saveSettingsButton"].tap()
        attach("基础设置语言")
        app.tabBars.buttons["翻译"].tap()
        for _ in 0..<4 where !app.buttons["swapLanguagesButton"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.buttons["sourceLanguagePicker"].label.contains("日语"))
        XCTAssertTrue(app.buttons["targetLanguagePicker"].label.contains("英语"))
        app.buttons["swapLanguagesButton"].tap()
        XCTAssertTrue(app.buttons["sourceLanguagePicker"].label.contains("英语"))
        XCTAssertTrue(app.buttons["targetLanguagePicker"].label.contains("日语"))
    }

    @MainActor private func selectLanguage(_ identifier: String, title: String) {
        let picker = app.buttons[identifier]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let options = app.buttons.matching(identifier: title)
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 5))
        options.element(boundBy: options.count - 1).tap()
    }
    @MainActor func testProviderPresetSelectionAndPromptSaveRemainSeparate() {
        launch()
        app.tabBars.buttons["设置"].tap()
        openSettings("apiSettingsLink")
        selectLanguage("providerPicker", title: "DeepSeek")
        app.buttons["chooseModelButton"].tap()
        XCTAssertTrue(app.buttons["model-deepseek-v4-pro"].waitForExistence(timeout: 5))
        app.buttons["model-deepseek-v4-pro"].tap()
        app.buttons["saveSettingsButton"].tap()
        attach("主流AI预设")
        app.navigationBars.buttons["设置"].tap()
        openSettings("promptSettingsLink")
        let editor = app.textViews["customPromptEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap(); editor.typeText("Keep names. {target_language}")
        app.buttons["savePromptButton"].tap()
        XCTAssertTrue(app.staticTexts["promptSavedNotice"].waitForExistence(timeout: 5))
        attach("自定义提示词")
        app.navigationBars.buttons["设置"].tap()
        openSettings("apiSettingsLink")
        XCTAssertTrue(app.buttons["chooseModelButton"].label.contains("deepseek-v4-pro"))
        app.navigationBars.buttons["设置"].tap()
        openSettings("promptSettingsLink")
        XCTAssertTrue(app.textViews["customPromptEditor"].value as? String == "Keep names. {target_language}")
    }
    @MainActor func testMinimalHomeAndClearInputKeepsActionsAvailable() {
        launch()
        XCTAssertFalse(app.buttons["shortcutGuide"].exists)
        XCTAssertFalse(app.staticTexts["设置操作按钮"].exists)
        XCTAssertFalse(app.buttons["translateButton"].isEnabled)
        XCTAssertTrue(app.buttons["choosePhoto"].exists)
        XCTAssertTrue(app.buttons["chooseFile"].exists)
        attach("极简翻译首页")
        let editor = app.textViews["sourceEditor"]
        editor.tap(); editor.typeText("Hello")
        XCTAssertTrue(app.buttons["translateButton"].isEnabled)
        app.buttons["clearInputButton"].tap()
        XCTAssertEqual(editor.value as? String, "")
        XCTAssertFalse(app.buttons["translateButton"].isEnabled)
        editor.tap(); editor.typeText("   ")
        XCTAssertFalse(app.buttons["translateButton"].isEnabled)
        XCTAssertTrue(app.buttons["clearInputButton"].exists)
        app.buttons["clearInputButton"].tap()
        XCTAssertEqual(editor.value as? String, "")
        app.tabBars.buttons["设置"].tap()
        XCTAssertFalse(app.buttons["simulatorActionButtonLink"].exists)
        XCTAssertFalse(app.staticTexts["模拟操作按钮"].exists)
    }
    @MainActor func testEditingSourceClearsStaleTranslation() {
        launch()
        translate("Hello!")
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 10))
        let editor = app.textViews["sourceEditor"]
        for _ in 0..<4 where !editor.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.3))
                .press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.7)))
        }
        editor.tap(); editor.typeText(" Updated.")
        XCTAssertFalse(app.staticTexts["translationResult"].exists)
        if app.buttons["完成"].exists { app.buttons["完成"].tap() }
        XCTAssertTrue(app.buttons["translateButton"].isEnabled)
    }
    @MainActor func testLongResultScrollsToLastParagraphInRecentResult() {
        launch(extra: ["--fixture-long"])
        translate("A long screen of text")
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 10))
        attach("紧凑长译文首段")
        app.buttons["recentResultButton"].tap()
        XCTAssertTrue(app.navigationBars["翻译记录"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyRow-'")).firstMatch.tap()
        let scroll = app.scrollViews["recentResultScroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let end = scroll.staticTexts["translationParagraph-24"]
        for _ in 0..<16 where !end.isHittable { scroll.swipeUp() }
        attach("长文滚动检查")
        if !end.isHittable {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "长文滚动界面结构"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(end.isHittable, "Last paragraph must be visible after scrolling")
        XCTAssertTrue(end.label.contains("全文结束"))
        attach("全文最后一段")
    }

    @MainActor func testVisualModeShowsDisclosureAndProducesSeparateOverview() {
        launch(extra: ["--fixture-image"])
        let picker = app.segmentedControls["translationModePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["识图"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '发送图片'")).firstMatch.exists)
        XCTAssertFalse(app.textViews["sourceEditor"].exists)
        attach("看图模式与上传说明")
        app.buttons["translateButton"].tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["translationParagraph-1"].label.contains("画面大意"))
        attach("看图理解结果")
    }
    @MainActor func testProfessionalModeKeepsBlocksAndSavedDefault() {
        launch()
        app.segmentedControls["translationModePicker"].buttons["专业"].tap()
        translate("Title\n\nDescription\n\nPrice: 1200")
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["translationResult"].label.contains("第1块"))
        XCTAssertTrue(app.staticTexts["translationParagraph-2"].label.contains("第3块"))
        attach("专业模式分段译文")
        app.tabBars.buttons["设置"].tap()
        openSettings("basicSettingsLink")
        XCTAssertTrue(app.buttons["defaultModePicker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["defaultModePicker"].label.contains("专业"))
        let ask = app.switches["askModeInShortcutsToggle"]
        for _ in 0..<3 where !ask.isHittable { app.swipeUp() }
        ask.tap()
        app.buttons["saveSettingsButton"].tap()
        attach("默认模式与每次询问")
    }

    @MainActor func testSystemEngineShowsSimulatorBoundaryInsteadOfCallingAPI() {
        launch(error: true)
        app.tabBars.buttons["设置"].tap()
        openSettings("basicSettingsLink")
        app.segmentedControls["translationServicePicker"].buttons["系统翻译"].tap()
        attach("系统翻译服务设置")
        app.tabBars.buttons["翻译"].tap()
        XCTAssertFalse(app.segmentedControls["translationModePicker"].exists)
        XCTAssertTrue(app.staticTexts["系统翻译"].exists)
        translate("Hello")
        let error = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '真机'")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '401'")).firstMatch.exists)
        attach("系统机翻入口与边界")
    }

    @MainActor func testVisualModeRequiresImageAndCanSwitchBack() {
        launch()
        app.segmentedControls["translationModePicker"].buttons["识图"].tap()
        XCTAssertFalse(app.buttons["translateButton"].isEnabled)
        XCTAssertFalse(app.textViews["sourceEditor"].exists)
        XCTAssertTrue(app.buttons["choosePhoto"].exists)
        attach("识图模式首页")
        app.segmentedControls["translationModePicker"].buttons["快速"].tap()
        XCTAssertTrue(app.textViews["sourceEditor"].exists)
        attach("快速模式首页")
    }

    @MainActor func testServiceRestrictionsAndAppearanceSelection() {
        launch()
        app.segmentedControls["translationModePicker"].buttons["专业"].tap()
        app.tabBars.buttons["设置"].tap()
        openSettings("basicSettingsLink")
        app.segmentedControls["translationServicePicker"].buttons["系统翻译"].tap()
        XCTAssertEqual(app.buttons["defaultModePicker"].label.contains("快速"), true)
        app.tabBars.buttons["翻译"].tap()
        XCTAssertFalse(app.segmentedControls["translationModePicker"].exists)
        app.tabBars.buttons["设置"].tap()
        app.segmentedControls["translationServicePicker"].buttons["AI 翻译"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        openSettings("appearanceSettingsLink")
        app.segmentedControls["appearancePicker"].buttons["浅色"].tap()
        app.buttons["accent-terracotta"].tap()
        XCTAssertEqual(app.buttons["accent-terracotta"].value as? String, "已选")
        attach("纸白陶土配色")
        app.tabBars.buttons["翻译"].tap()
        XCTAssertTrue(app.segmentedControls["translationModePicker"].buttons["专业"].exists)
        let editor = app.textViews["sourceEditor"]
        editor.tap(); editor.typeText("A quiet place to read.")
        if app.buttons["完成"].exists { app.buttons["完成"].tap() }
        attach("纸白翻译首页")
        app.tabBars.buttons["设置"].tap()
        XCTAssertEqual(app.buttons["accent-terracotta"].value as? String, "已选")
        app.segmentedControls["appearancePicker"].buttons["深色"].tap()
        app.buttons["accent-blue"].tap()
        attach("深色海蓝配色")
        app.buttons["accent-custom"].tap()
        let color = app.descendants(matching: .any).matching(identifier: "customColorPicker").firstMatch
        for _ in 0..<3 where !color.isHittable { app.swipeUp() }
        XCTAssertTrue(color.waitForExistence(timeout: 5))
        app.tabBars.buttons["翻译"].tap()
        attach("深色翻译首页")
    }

    @MainActor func testHistorySearchDeleteAndFullDetail() {
        launch(extra: ["--fixture-history"])
        app.buttons["recentResultButton"].tap()
        XCTAssertTrue(app.navigationBars["翻译记录"].waitForExistence(timeout: 5))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyRow-'"))
        XCTAssertEqual(rows.count, 3)
        attach("多条翻译记录")
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("coffee")
        XCTAssertEqual(rows.count, 1)
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["translationResult"].label.contains("咖啡"))
        app.navigationBars.buttons.firstMatch.tap()
        let cancel = app.buttons["取消"]
        if cancel.exists { cancel.tap() }
        else if app.buttons["取消"].exists { app.buttons["取消"].tap() }
        rows.firstMatch.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertEqual(rows.count, 2)
        app.buttons["清空"].tap()
        app.buttons["清空记录"].tap()
        XCTAssertTrue(app.staticTexts["还没有翻译记录"].waitForExistence(timeout: 5))
    }

    @MainActor func testReaderPreferencesApplyToHistory() {
        launch(extra: ["--fixture-history"])
        app.tabBars.buttons["设置"].tap()
        openSettings("readerSettingsLink")
        app.segmentedControls["readerTextSizePicker"].buttons["较大"].tap()
        app.segmentedControls["readerSpacingPicker"].buttons["宽松"].tap()
        let toggle = app.switches["readerOriginalToggle"]
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        attach("译文显示自定义")
        app.tabBars.buttons["翻译"].tap()
        app.buttons["recentResultButton"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyRow-'" )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "阅读设置应用详情结构"; tree.lifetime = .keepAlways; add(tree)
        attach("原文展开检查")
        XCTAssertTrue(app.staticTexts["Open the window."].waitForExistence(timeout: 5))
        attach("自定义译文阅读界面")
    }

    @MainActor private func openSettings(_ identifier: String) {
        if ["appearanceSettingsLink", "readerSettingsLink"].contains(identifier), !app.buttons[identifier].exists {
            openSettings("displaySettingsLink")
        }
        let link = app.buttons[identifier]
        for _ in 0..<3 where !link.isHittable { app.swipeUp() }
        for _ in 0..<4 where !link.isHittable { app.swipeDown() }
        XCTAssertTrue(link.isHittable); link.tap()
    }

    @MainActor private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
