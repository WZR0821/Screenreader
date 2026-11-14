import XCTest

/// The translation page and the settings page each fill one screen exactly:
/// the content is as tall as the room between the bars, the last element ends
/// just above the tab bar, and nothing moves on a swipe. A shorter phone gets
/// the same; only a screen too short for the content scrolls.
final class OneScreenUITests: XCTestCase {
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
    @MainActor private func any(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    @MainActor private var lastRecent: XCUIElement {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboardResult-'"))
        return rows.element(boundBy: max(rows.count - 1, 0))
    }

    /// What the page's scroll view reports about itself in test builds.
    @MainActor private func reading(_ page: String) -> [String: CGFloat] {
        let probe = any(page + "Probe")
        XCTAssertTrue(probe.waitForExistence(timeout: 5), page)
        var values: [String: CGFloat] = [:]
        for part in probe.label.split(separator: " ") {
            let pair = part.split(separator: "=")
            if pair.count == 2, let number = Double(pair[1]) { values[String(pair[0])] = CGFloat(number) }
        }
        return values
    }

    /// The page is one screen: content as tall as its room, still after swipes
    /// in both directions, and `last` ending `gap` points above the bottom.
    @MainActor private func assertOneScreen(_ page: String, last: XCUIElement, gap: ClosedRange<CGFloat>,
                                            shorter: CGFloat = 0, _ name: String) {
        XCTAssertTrue(last.waitForExistence(timeout: 5), name)
        let before = last.frame
        app.swipeUp(); app.swipeDown(); app.swipeUp(); app.swipeDown()
        let values = reading(page)
        XCTAssertEqual(values["content"] ?? -1, values["room"] ?? -2, accuracy: 0.5, "\(name): \(values)")
        XCTAssertEqual(values["moved"] ?? -1, 0, accuracy: 0.5, "\(name) moved: \(values)")
        XCTAssertEqual(last.frame.minY, before.minY, accuracy: 0.5, name)
        let space = app.tabBars.firstMatch.frame.minY - shorter - last.frame.maxY
        XCTAssertTrue(gap.contains(space), "\(name): \(space) points under the last element")
    }

    @MainActor func testBothMainScreensFillOneScreen() {
        launch(["--fixture-history"])
        let title = app.navigationBars["翻译"].frame.height
        assertOneScreen("translationScroll", last: lastRecent, gap: 8...20, "翻译")
        XCTAssertEqual(app.navigationBars["翻译"].frame.height, title, "The large title stays large")
        attach("1.3.2-home-translation")
        app.tabBars.buttons["设置"].tap()
        assertOneScreen("settingsAccessibleScroll", last: app.staticTexts["appVersionLabel"], gap: 4...16, "设置")
        attach("1.3.2-home-settings")
    }

    @MainActor func testBothMainScreensInDarkAppearance() {
        launch(["--fixture-history", "--fixture-dark"])
        assertOneScreen("translationScroll", last: lastRecent, gap: 8...20, "翻译")
        attach("1.3.2-home-translation-dark")
        app.tabBars.buttons["设置"].tap()
        assertOneScreen("settingsAccessibleScroll", last: app.staticTexts["appVersionLabel"], gap: 4...16, "设置")
        attach("1.3.2-home-settings-dark")
    }

    @MainActor func testTranslationPageFillsWithNoRecordAndWithOne() {
        launch()
        assertOneScreen("translationScroll", last: any("recentTranslationsEmpty"), gap: 8...20, "没有记录")
        attach("1.3.2-home-translation-empty")

        // Typing brings the keyboard up and the page scrolls. Pulling the page
        // down puts the keyboard away, and the page is one screen again.
        let button = app.buttons["translateButton"], resting = button.frame
        let editor = app.textViews["sourceEditor"]
        editor.tap(); editor.typeText("Good morning.")
        attach("1.3.2-home-translation-keyboard")
        app.swipeDown()
        if app.buttons["完成"].waitForExistence(timeout: 1) { app.buttons["完成"].tap() }
        let deadline = Date().addingTimeInterval(5)
        while abs(button.frame.minY - resting.minY) >= 0.5, Date() < deadline { usleep(200_000) }
        XCTAssertEqual(button.frame.minY, resting.minY, accuracy: 0.5, "The page comes back to where it was")
        let afterKeyboard = reading("translationScroll")
        XCTAssertEqual(afterKeyboard["content"] ?? -1, afterKeyboard["room"] ?? -2, accuracy: 0.5, "\(afterKeyboard)")
        let emptyCard = any("recentTranslationsEmpty")
        let under = app.tabBars.firstMatch.frame.minY - emptyCard.frame.maxY
        XCTAssertTrue((8...20).contains(under), "After the keyboard: \(under) points under the last element")

        button.tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 15))
        app.navigationBars["译文"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(lastRecent.waitForExistence(timeout: 5))
        let values = reading("translationScroll")
        XCTAssertEqual(values["content"] ?? -1, values["room"] ?? -2, accuracy: 0.5, "One record: \(values)")
        let space = app.tabBars.firstMatch.frame.minY - lastRecent.frame.maxY
        XCTAssertTrue((8...20).contains(space), "One record: \(space) points under it")
        attach("1.3.2-home-translation-one-record")
    }

    @MainActor func testShorterPhonesStillGetOneScreen() {
        // 19 and 50 points less stand in for the 6.1-inch and the mini sizes.
        for shorter in [19, 50] {
            launch(["--fixture-history", "--fixture-shorter=\(shorter)"])
            assertOneScreen("translationScroll", last: lastRecent, gap: 8...20, shorter: CGFloat(shorter), "翻译 −\(shorter)")
            attach("1.3.2-home-translation-shorter-\(shorter)")
            app.tabBars.buttons["设置"].tap()
            assertOneScreen("settingsAccessibleScroll", last: app.staticTexts["appVersionLabel"], gap: 4...16,
                            shorter: CGFloat(shorter), "设置 −\(shorter)")
            attach("1.3.2-home-settings-shorter-\(shorter)")
            app.terminate()
        }
    }

    @MainActor func testAPageALittleTooTallScrollsAndComesBack() {
        // Take more and more off the bottom until the translation page cannot
        // be that short. It is then too tall by less than the large title is
        // high: it scrolls, the title gives way, and both come back.
        var shorter = 60, start: [String: CGFloat] = [:]
        repeat {
            app?.terminate()
            shorter += 10
            launch(["--fixture-history", "--fixture-shorter=\(shorter)"])
            XCTAssertTrue(lastRecent.waitForExistence(timeout: 5))
            start = reading("translationScroll")
            print("ONESCREEN shorter=\(shorter) \(start)")
        } while (start["content"] ?? 0) <= (start["room"] ?? 0) + 1 && shorter < 220
        XCTAssertGreaterThan(start["content"] ?? 0, (start["room"] ?? 0) + 1, "−\(shorter): \(start)")
        let bar = app.navigationBars["翻译"], last = lastRecent
        let barHeight = bar.frame.height, lastTop = last.frame.minY
        attach("1.3.2-home-translation-too-short")
        app.swipeUp()
        XCTAssertGreaterThan(reading("translationScroll")["moved"] ?? 0, 1)
        attach("1.3.2-home-translation-too-short-scrolled")
        app.swipeDown(); app.swipeDown()
        XCTAssertEqual(bar.frame.height, barHeight, accuracy: 0.5, "The large title comes back")
        XCTAssertEqual(last.frame.minY, lastTop, accuracy: 0.5, "The page comes back")
        let end = reading("translationScroll")
        XCTAssertEqual(end["content"] ?? -1, start["content"] ?? -2, accuracy: 0.5, "The page keeps its own height: \(end)")
    }

    /// Types with the keyboard up and scrolls the page above it until the
    /// large title has collapsed.
    @MainActor private func typeAndScrollAboveTheKeyboard(_ name: String) -> (large: CGFloat, resting: CGFloat) {
        let bar = app.navigationBars["翻译"], button = app.buttons["translateButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let large = bar.frame.height, resting = button.frame.minY
        let editor = app.textViews["sourceEditor"]
        editor.tap(); editor.typeText("Good morning.")
        // From the edge of the input card, beside its buttons: a drag that
        // starts on the text would select it instead.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.935, dy: 0.535))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.935, dy: 0.2)))
        usleep(800_000)
        attach("1.3.2-home-translation-keyboard-scrolled-\(name)")
        print("ONESCREEN \(name) scrolled: bar \(large) -> \(bar.frame.height) \(reading("translationScroll"))")
        XCTAssertLessThan(bar.frame.height, large - 1, "Scrolling above the keyboard collapses the title")
        return (large, resting)
    }

    /// The page is back to one screen under the large title.
    @MainActor private func assertBack(_ state: (large: CGFloat, resting: CGFloat), last: XCUIElement, _ name: String) {
        let bar = app.navigationBars["翻译"], button = app.buttons["translateButton"]
        let deadline = Date().addingTimeInterval(5)
        while abs(button.frame.minY - state.resting) >= 0.5 || abs(bar.frame.height - state.large) >= 0.5, Date() < deadline {
            usleep(200_000)
        }
        usleep(600_000)
        attach("1.3.2-home-translation-back-\(name)")
        let values = reading("translationScroll")
        print("ONESCREEN \(name) back: bar \(bar.frame.height) button \(button.frame.minY) resting \(state.resting) \(values)")
        XCTAssertEqual(bar.frame.height, state.large, accuracy: 0.5, "\(name): the large title comes back")
        XCTAssertEqual(button.frame.minY, state.resting, accuracy: 0.5, "\(name): the page comes back to where it was")
        XCTAssertEqual(values["content"] ?? -1, values["room"] ?? -2, accuracy: 0.5, "\(name): \(values)")
        let space = app.tabBars.firstMatch.frame.minY - last.frame.maxY
        XCTAssertTrue((8...20).contains(space), "\(name): \(space) points under the last element")
    }

    @MainActor func testThePageComesBackWhenDoneIsTappedWithTheTitleCollapsed() {
        launch()
        // More than once: left to itself the title came back in one run and
        // stayed collapsed in another.
        for round in 1...3 {
            let state = typeAndScrollAboveTheKeyboard("done-\(round)")
            app.buttons["完成"].tap()
            assertBack(state, last: any("recentTranslationsEmpty"), "done-\(round)")
        }
    }

    @MainActor func testThePageComesBackAfterTranslatingWithTheTitleCollapsed() {
        launch()
        let state = typeAndScrollAboveTheKeyboard("translate")
        app.buttons["translateButton"].tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 15))
        app.navigationBars["译文"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(lastRecent.waitForExistence(timeout: 5))
        // The record now on the page moves the button; only the title and the fit are compared.
        let bar = app.navigationBars["翻译"]
        let deadline = Date().addingTimeInterval(5)
        while abs(bar.frame.height - state.large) >= 0.5, Date() < deadline { usleep(200_000) }
        usleep(600_000)
        attach("1.3.2-home-translation-back-translate")
        let values = reading("translationScroll")
        print("ONESCREEN translate back: bar \(bar.frame.height) \(values)")
        XCTAssertEqual(bar.frame.height, state.large, accuracy: 0.5, "The large title comes back")
        XCTAssertEqual(values["content"] ?? -1, values["room"] ?? -2, accuracy: 0.5, "\(values)")
        let space = app.tabBars.firstMatch.frame.minY - lastRecent.frame.maxY
        XCTAssertTrue((8...20).contains(space), "\(space) points under the record")
    }

    /// Goes to the page `open` leads to and comes back. The main screen is
    /// then as it was: same title, same place, still one screen.
    @MainActor private func assertUnchangedByAVisit(_ page: String, title: String, open: XCUIElement, last: XCUIElement) {
        XCTAssertTrue(last.waitForExistence(timeout: 5), title)
        let bar = app.navigationBars[title]
        let height = bar.frame.height, place = last.frame.minY
        open.tap()
        let back = app.navigationBars.buttons[title]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "\(title): the other page")
        back.tap()
        XCTAssertTrue(last.waitForExistence(timeout: 5), title)
        let deadline = Date().addingTimeInterval(5)
        while abs(bar.frame.height - height) >= 0.5 || abs(last.frame.minY - place) >= 0.5, Date() < deadline { usleep(200_000) }
        usleep(900_000)
        let values = reading(page)
        print("ONESCREEN \(title) after a visit: bar \(bar.frame.height) of \(height) last \(last.frame.minY) of \(place) \(values)")
        XCTAssertEqual(bar.frame.height, height, accuracy: 0.5, "\(title): the large title")
        XCTAssertEqual(last.frame.minY, place, accuracy: 0.5, "\(title): the page is where it was")
        XCTAssertEqual(values["content"] ?? -1, values["room"] ?? -2, accuracy: 0.5, "\(title): \(values)")
        XCTAssertEqual(values["moved"] ?? -1, 0, accuracy: 0.5, "\(title) moved: \(values)")
    }

    @MainActor func testTheMainScreensAreAsTheyWereAfterAVisitElsewhere() {
        launch(["--fixture-history"])
        assertUnchangedByAVisit("translationScroll", title: "翻译", open: lastRecent, last: lastRecent)
        let place = lastRecent.frame.minY
        app.tabBars.buttons["设置"].tap()
        assertUnchangedByAVisit("settingsAccessibleScroll", title: "设置", open: app.buttons["basicSettingsLink"],
                                last: app.staticTexts["appVersionLabel"])
        app.tabBars.buttons["翻译"].tap()
        XCTAssertTrue(lastRecent.waitForExistence(timeout: 5))
        usleep(900_000)
        let values = reading("translationScroll")
        print("ONESCREEN 翻译 after the other tab: last \(lastRecent.frame.minY) of \(place) \(values)")
        XCTAssertEqual(lastRecent.frame.minY, place, accuracy: 0.5, "After the other tab")
        XCTAssertEqual(values["content"] ?? -1, values["room"] ?? -2, accuracy: 0.5, "After the other tab: \(values)")
        XCTAssertEqual(values["moved"] ?? -1, 0, accuracy: 0.5, "After the other tab, moved: \(values)")
    }

    @MainActor func testAScreenTooShortScrollsInstead() {
        launch(["--fixture-history", "--fixture-shorter=150"])
        app.tabBars.buttons["设置"].tap()
        let version = app.staticTexts["appVersionLabel"]
        XCTAssertTrue(app.buttons["basicSettingsLink"].waitForExistence(timeout: 5))
        let values = reading("settingsAccessibleScroll")
        XCTAssertGreaterThan(values["content"] ?? 0, (values["room"] ?? 0) + 1, "\(values)")
        attach("1.3.2-home-settings-too-short")
        for _ in 0..<4 where !(version.exists && version.frame.maxY <= app.tabBars.firstMatch.frame.minY - 150) { app.swipeUp() }
        XCTAssertLessThanOrEqual(version.frame.maxY, app.tabBars.firstMatch.frame.minY - 150 + 0.5)
        XCTAssertGreaterThan(reading("settingsAccessibleScroll")["moved"] ?? 0, 1)
    }
}
