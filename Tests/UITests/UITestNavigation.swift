import XCTest

extension XCUIApplication {
    @MainActor func showReadingPresentation() {
        let picker = segmentedControls["translationPresentationPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 40))
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
