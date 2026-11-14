import XCTest

extension XCUIApplication {
    /// Waits for a result and leaves it in reading form. Since 1.3.3 原图直译 is
    /// optional: without it the result opens as text and has no picker.
    @MainActor func showReadingPresentation() {
        let picker = segmentedControls["translationPresentationPicker"]
        let copy = buttons["copyTranslation"]
        let deadline = Date().addingTimeInterval(40)
        while !picker.exists && !copy.exists && Date() < deadline { _ = copy.waitForExistence(timeout: 1) }
        XCTAssertTrue(picker.exists || copy.exists, "No translation result appeared")
        guard picker.exists else { return }
        revealForNavigation(picker); picker.buttons["阅读"].tap()
    }
    @MainActor func revealForNavigation(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.isHittable && element.frame.minY > 100 && element.frame.maxY < frame.maxY - 90 { return }
            if element.exists && element.frame.minY < 100 { swipeDown() } else { swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor func openTranslationHistory() {
        if navigationBars["译文"].exists { navigationBars["译文"].buttons.element(boundBy: 0).tap() }
        let all = buttons["dashboardAllHistory"]
        revealForNavigation(all); all.tap()
        XCTAssertTrue(navigationBars["翻译记录"].waitForExistence(timeout: 5))
    }
}
