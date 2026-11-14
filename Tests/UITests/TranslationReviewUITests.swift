import XCTest

final class TranslationReviewUITests: XCTestCase {
    @MainActor private func app(table: Bool = false, failure: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--fixture-image", "--fixture-layout", "--fixture-reader-collapsed"]
        if table { app.launchArguments.append("--fixture-review-table") }
        if failure { app.launchArguments.append("--fixture-review-error") }
        app.launch()
        app.buttons["translateButton"].tap()
        XCTAssertTrue(app.buttons["copyTranslation"].waitForExistence(timeout: 40))
        app.showReadingPresentation()
        return app
    }
    @MainActor private func source(_ app: XCUIApplication, column: Int = 0) -> XCUIElement {
        let id = "translationReviewSource-\(column)"
        return app.descendants(matching: .any)[id]
    }
    @MainActor private func replace(_ element: XCUIElement, with text: String, column: Int = 0) {
        let app = XCUIApplication()
        let clear = app.buttons["clearReviewSource-\(column)"]
        reveal(app, clear); clear.tap()
        expectation(for: NSPredicate(format: "value == '' OR value == '本段原文' OR value BEGINSWITH '本列原文'"), evaluatedWith: element)
        waitForExpectations(timeout: 5)
        reveal(app, element)
        element.tap()
        element.typeText(text)
        XCTAssertEqual(element.value as? String, text)
    }
    @MainActor private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        // SwiftUI reports partially clipped list rows as hittable. Bring the
        // entire editor/control above the home indicator before tapping it.
        for _ in 0..<10 where !element.isHittable || element.frame.maxY > app.frame.maxY - 35 {
            if element.exists && element.frame.minY < app.frame.minY + 100 { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testParagraphImageReviewEditsOneBlockAndHistoryReflectsChange() {
        let app = app()
        let paragraph = app.staticTexts["translationParagraph-1"]
        reveal(app, paragraph); paragraph.tap()
        XCTAssertFalse(app.navigationBars["核对译文"].exists, "Selecting reading text must not open a review sheet")
        app.buttons["reviewTranslationBlock-2"].tap()
        XCTAssertTrue(app.navigationBars["核对译文"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["translationReviewCrop"].waitForExistence(timeout: 5))
        app.buttons["translationReviewCrop"].tap()
        XCTAssertTrue(app.navigationBars["原图区域"].waitForExistence(timeout: 3))
        app.navigationBars["原图区域"].buttons["完成"].tap()
        let editor = source(app)
        reveal(app, editor)
        XCTAssertTrue((editor.value as? String ?? "").contains("Freshly"))
        replace(editor, with: "Freshly made every morning. Served until noon. Order number 19.")
        app.buttons["finishReviewEditing"].tap()
        capture(app, name: "译文核对-原文与原图")
        reveal(app, app.buttons["retranslateBlock"]); app.buttons["retranslateBlock"].tap()
        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: app.navigationBars["核对译文"])
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["reviewTranslationBlock-2"].exists)
        XCTAssertTrue(app.staticTexts["translationParagraph-1"].label.contains("19"))
        XCTAssertEqual(app.staticTexts["translationResult"].label, "早餐菜单")
        reveal(app, app.staticTexts["translationReviewSummary"])
        XCTAssertTrue(app.staticTexts["translationReviewSummary"].label.contains("1 段"))
        if app.navigationBars["译文"].exists { app.navigationBars["译文"].buttons.element(boundBy: 0).tap() }
        app.openTranslationHistory()
        let history = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyRow-'"))
        XCTAssertEqual(history.count, 1)
        history.firstMatch.tap()
        let detail = app.scrollViews["recentResultScroll"]
        XCTAssertTrue(detail.staticTexts["translationParagraph-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(detail.staticTexts["translationParagraph-1"].label.contains("19"))
        detail.buttons["reviewTranslationBlock-2"].tap()
        XCTAssertTrue(app.navigationBars["核对译文"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["translationReviewCrop"].exists)
        XCTAssertTrue((source(app).value as? String ?? "").contains("19"))
    }

    @MainActor func testFailureAndClosingDraftRetainPreviousTranslation() {
        let app = app(failure: true)
        let button = app.buttons["reviewTranslationBlock-1"]
        reveal(app, button); button.tap()
        XCTAssertTrue(app.navigationBars["核对译文"].waitForExistence(timeout: 5))
        let editor = source(app); reveal(app, editor); replace(editor, with: "REVIEW_FAIL")
        app.buttons["finishReviewEditing"].tap()
        reveal(app, app.buttons["retranslateBlock"]); app.buttons["retranslateBlock"].tap()
        XCTAssertTrue(app.staticTexts["errorBanner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["errorBanner"].label.contains("401"))
        capture(app, name: "译文核对-失败保留旧译文")
        app.buttons["closeTranslationReview"].tap()
        XCTAssertTrue(app.staticTexts["translationResult"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["translationResult"].label, "早餐菜单")
        XCTAssertFalse(app.staticTexts["translationReviewSummary"].exists)
        button.tap()
        XCTAssertTrue(app.navigationBars["核对译文"].waitForExistence(timeout: 3))
        XCTAssertEqual(source(app).value as? String, "Breakfast menu")
    }

    @MainActor func testTableReviewKeepsCellsAndOtherRows() {
        let app = app(table: true)
        XCTAssertTrue(app.scrollViews["translationTable"].exists, app.debugDescription)
        let row = app.buttons["reviewTranslationBlock-2"]
        // The row's control is at the right edge of the horizontal table.
        app.scrollViews["translationTable"].swipeLeft()
        reveal(app, row); row.tap()
        XCTAssertTrue(app.navigationBars["核对译文"].waitForExistence(timeout: 5))
        XCTAssertTrue(source(app, column: 0).exists); XCTAssertTrue(source(app, column: 1).exists)
        let amount = source(app, column: 2); reveal(app, amount)
        XCTAssertTrue((amount.value as? String ?? "").contains("450"))
        replace(amount, with: "460 yen", column: 2)
        app.buttons["finishReviewEditing"].tap()
        capture(app, name: "译文核对-表格逐列核对")
        reveal(app, app.buttons["retranslateBlock"]); app.buttons["retranslateBlock"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["核对译文"])
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.descendants(matching: .any)["translationParagraph-1"].label.contains("460"))
        XCTAssertTrue(app.descendants(matching: .any)["translationParagraph-2"].label.contains("300"))
    }
}
