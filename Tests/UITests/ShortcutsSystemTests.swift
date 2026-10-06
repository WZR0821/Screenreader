import XCTest

final class ShortcutsSystemTests: XCTestCase {
    @MainActor func testImportFullShortcutAndReadLastParagraphInSystemQuickLook() {
        continueAfterFailure = false
        // Dismiss a previous system reader/runner before importing another copy.
        XCUIApplication(bundleIdentifier: "com.apple.shortcuts").terminate()
        XCUIDevice.shared.press(.home)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--fixture-long", "--fixture-askmode", "--fixture-reader", "--fixture-reader-collapsed"]
        app.launch()
        app.tabBars.buttons["设置"].tap()
        let entry = app.buttons["fullScreenShortcutLink"]
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.buttons["importFullShortcut"].waitForExistence(timeout: 5))
        app.buttons["importFullShortcut"].tap()
        let shareDebug = XCTAttachment(string: app.debugDescription)
        shareDebug.name = "分享指令文件界面"; shareDebug.lifetime = .keepAlways; add(shareDebug)
        let shareTarget = app.cells.containing(NSPredicate(format: "label == %@", "快捷指令")).firstMatch
        if shareTarget.waitForExistence(timeout: 5) { shareTarget.tap() }
        else if app.staticTexts["快捷指令"].firstMatch.exists { app.staticTexts["快捷指令"].firstMatch.tap() }
        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        let addButton = shortcuts.buttons["添加快捷指令"]
        if !addButton.waitForExistence(timeout: 15) {
            let debug = XCTAttachment(string: app.debugDescription + "\n" + shortcuts.debugDescription)
            debug.name = "导入诊断"; debug.lifetime = .keepAlways; add(debug)
        }
        XCTAssertTrue(addButton.exists)
        addButton.tap()
        for name in ["替换", "Replace", "添加"] where shortcuts.buttons[name].exists { shortcuts.buttons[name].tap() }
        if shortcuts.buttons["运行快捷指令"].waitForExistence(timeout: 5) {
            shortcuts.buttons["运行快捷指令"].tap()
        } else {
            if shortcuts.navigationBars.buttons["快捷指令"].exists { shortcuts.navigationBars.buttons["快捷指令"].tap() }
            let full = shortcuts.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "读屏全文")).firstMatch
            if !full.waitForExistence(timeout: 5) { shortcuts.swipeDown() }
            XCTAssertTrue(full.waitForExistence(timeout: 5), shortcuts.debugDescription)
            full.tap()
        }
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var pickedMode = false
        for _ in 0..<15 {
            if system.webViews["QLWKWebViewControllerWkWebViewAccessibilityIdentifier"].waitForExistence(timeout: 3) { break }
            for owner in [shortcuts, system] {
                let choice = owner.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "快速")).firstMatch
                if choice.exists {
                    let modes = XCTAttachment(screenshot: system.screenshot())
                    modes.name = "操作按钮选择模式"; modes.lifetime = .keepAlways; add(modes)
                    choice.tap(); pickedMode = true
                }
                for label in ["始终允许", "Always Allow", "允许一次", "Allow Once", "允许", "Allow"] {
                    if owner.buttons[label].exists { owner.buttons[label].tap(); break }
                }
            }
        }
        XCTAssertTrue(pickedMode, "Saved ask preference should prompt before translation")
        let debug = XCTAttachment(string: shortcuts.debugDescription + "\n" + system.debugDescription)
        debug.name = "全文弹窗界面结构"; debug.lifetime = .keepAlways; add(debug)
        let screenshot = XCTAttachment(screenshot: system.screenshot()); screenshot.name = "全文弹窗首屏"; screenshot.lifetime = .keepAlways; add(screenshot)
        let reader = system.webViews["QLWKWebViewControllerWkWebViewAccessibilityIdentifier"]
        XCTAssertTrue(reader.waitForExistence(timeout: 10), shortcuts.debugDescription)
        let close = system.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "QLOverlayDoneButtonAccessibilityIdentifier", ["完成", "Done", "关闭", "Close"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "System close control must be visible on presentation")
        XCTAssertTrue(close.isHittable)
        let source = reader.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "截屏")).firstMatch
        let original = reader.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "查看原文")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        XCTAssertFalse(source.exists, "Collapsed original must not fill the translation window")
        original.tap()
        XCTAssertTrue(source.waitForExistence(timeout: 5), "Native disclosure must expose the original without script")
        let expanded = XCTAttachment(screenshot: system.screenshot()); expanded.name = "展开原文-1.8.1"; expanded.lifetime = .keepAlways; add(expanded)
        XCTAssertTrue(close.exists, "Expanding original must not hide the system close control")
        original.tap()
        XCTAssertFalse(source.exists, "Original can be collapsed again")
        let clean = XCTAttachment(screenshot: system.screenshot()); clean.name = "精简全文首屏-1.8.1"; clean.lifetime = .keepAlways; add(clean)
        // Check that tapping a non-interactive area does not make closing
        // unavailable in this runtime; do not change the system presentation.
        reader.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.25)).tap()
        XCTAssertTrue(close.exists)
        let last = reader.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "全文结束")).firstMatch
        // WK static text is not an interactive target. Its isHittable query can
        // fail on offscreen nodes; use the visible frame and drag within the
        // document, away from Quick Look's bottom toolbar / home gesture.
        func lastIsVisible() -> Bool {
            guard last.exists else { return false }
            let visible = reader.frame.insetBy(dx: 0, dy: 65)
            return !last.frame.isEmpty && visible.contains(last.frame)
        }
        for _ in 0..<20 where !lastIsVisible() {
            reader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(forDuration: 0.05, thenDragTo: reader.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28)))
        }
        XCTAssertTrue(lastIsVisible(), "Quick Look must expose the last paragraph")
        XCTAssertTrue(close.exists, "System close control must remain available after reading the final paragraph")
        let end = XCTAttachment(screenshot: system.screenshot()); end.name = "全文弹窗末段"; end.lifetime = .keepAlways; add(end)
        XCTAssertNotEqual(app.state, .runningForeground)
        XCTAssertTrue(close.isHittable); close.tap()
        // Run again without restarting Shortcuts: a completed reader must not
        // leave the next run stuck behind an old system presentation.
        XCTAssertTrue(shortcuts.buttons["运行快捷指令"].waitForExistence(timeout: 5))
        shortcuts.buttons["运行快捷指令"].tap()
        for _ in 0..<10 {
            if reader.waitForExistence(timeout: 3) { break }
            for owner in [shortcuts, system] {
                let choice = owner.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "快速")).firstMatch
                if choice.exists { choice.tap() }
                for label in ["始终允许", "Always Allow", "允许一次", "Allow Once", "允许", "Allow"] {
                    if owner.buttons[label].exists { owner.buttons[label].tap(); break }
                }
            }
        }
        XCTAssertTrue(reader.waitForExistence(timeout: 5))
        XCTAssertTrue(close.exists)
        XCTAssertTrue(reader.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "第1段")).firstMatch.waitForExistence(timeout: 5))
        let second = XCTAttachment(screenshot: system.screenshot()); second.name = "再次运行全文弹窗"; second.lifetime = .keepAlways; add(second)
        XCTAssertTrue(close.isHittable); close.tap()
        if shortcuts.buttons["完成"].exists { shortcuts.buttons["完成"].tap() }
    }

    @MainActor func testScreenshotActionCanBeAddedAndHasImageParameter() {
        continueAfterFailure = false
        XCUIApplication(bundleIdentifier: "com.apple.shortcuts").terminate()
        XCUIDevice.shared.press(.home)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test"]
        app.launch()
        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        shortcuts.launch()
        if shortcuts.buttons["完成"].exists { shortcuts.buttons["完成"].tap() }
        XCTAssertTrue(shortcuts.buttons["创建快捷指令"].waitForExistence(timeout: 10))
        shortcuts.buttons["创建快捷指令"].tap()
        let search = shortcuts.textFields["搜索操作"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        if shortcuts.buttons["Continue"].waitForExistence(timeout: 1) { shortcuts.buttons["Continue"].tap() }
        search.typeText("翻译截图全文")
        let translateAction = shortcuts.staticTexts["翻译截图全文"].firstMatch
        XCTAssertTrue(translateAction.waitForExistence(timeout: 10))
        translateAction.tap()
        let action = shortcuts.otherElements["editor.action.com.raydon.ScreenTranslate.TranslateScreenshotDocumentIntent"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.otherElements.containing(NSPredicate(format: "label CONTAINS %@", "图片")).firstMatch.exists)
        XCTAssertTrue(shortcuts.buttons["运行快捷指令"].isEnabled)
        let snapshot = XCTAttachment(screenshot: shortcuts.screenshot())
        snapshot.name = "图片输入快捷指令编辑器"; snapshot.lifetime = .keepAlways; add(snapshot)
        shortcuts.buttons["完成"].tap()
    }

    @MainActor func testSystemDiscoversActionsAndPresentsTranslationCard() {
        continueAfterFailure = false
        XCUIApplication(bundleIdentifier: "com.apple.shortcuts").terminate()
        XCUIDevice.shared.press(.home)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test"]
        app.launch()
        let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
        shortcuts.launch()
        if shortcuts.buttons["完成"].exists { shortcuts.buttons["完成"].tap() }
        for label in ["Continue", "继续", "Get Started", "开始使用"] {
            if shortcuts.buttons[label].waitForExistence(timeout: 2) { shortcuts.buttons[label].tap() }
        }
        if shortcuts.navigationBars.buttons["快捷指令"].exists { shortcuts.navigationBars.buttons["快捷指令"].tap() }
        // Saved test shortcuts can push an app's horizontal preview past four
        // items. Open the app's complete collection before querying its actions.
        let collection = shortcuts.buttons.matching(NSPredicate(format: "label IN %@", ["读屏", "Screenreader"])).firstMatch
        for _ in 0..<6 where !collection.exists { shortcuts.swipeUp() }
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        if !collection.isHittable { shortcuts.swipeUp() }
        collection.tap()
        // Accumulated saved shortcuts occupy the first (virtualized) section.
        // Scroll to the generated App Shortcut section before checking its actions.
        for _ in 0..<8 where !shortcuts.buttons["character.bubble"].exists { shortcuts.swipeUp() }
        XCTAssertFalse(shortcuts.buttons["text.viewfinder"].exists, "Do not recommend the legacy screenshot preview as an Action Button workflow")
        XCTAssertTrue(shortcuts.buttons["character.bubble"].waitForExistence(timeout: 5))
        XCTAssertFalse(shortcuts.buttons["button.programmable"].exists, "The test-only action must not appear in the app collection")
        shortcuts.buttons["character.bubble"].tap()
        // App Shortcut prompts and snippets are presented by the system runner,
        // whose accessibility tree belongs to SpringBoard rather than Shortcuts.
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let input = system.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 20), system.debugDescription)
        input.tap()
        input.typeText("Hello, world!")
        system.buttons.matching(NSPredicate(format: "label IN %@", ["完成", "Done"])).firstMatch.tap()
        let translation = system.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "你好，世界")).firstMatch
        XCTAssertTrue(translation.waitForExistence(timeout: 20), system.debugDescription)
        XCTAssertNotEqual(app.state, .runningForeground, "Translation must not open the main app")
        let attachment = XCTAttachment(string: system.debugDescription)
        attachment.name = "系统翻译卡片界面结构"
        attachment.lifetime = .keepAlways
        add(attachment)
        let screenshot = XCTAttachment(screenshot: system.screenshot())
        screenshot.name = "系统翻译结果卡片"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(shortcuts.state, .runningForeground)
        system.buttons.matching(NSPredicate(format: "label IN %@", ["完成", "Done"])).firstMatch.tap()
    }
}
