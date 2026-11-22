import XCTest

/// 1.4.0 (33): the 语言优先级 page says how screenshots, 识图 and the action
/// button decide, naming the language first in the order.
final class Release140ScreenUITests: XCTestCase {
    @MainActor func testThePriorityPageExplainsScreenshotsAndTheActionButton() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-test"]; app.launch()
        app.tabBars.buttons["设置"].tap()
        let basic = app.buttons["basicSettingsLink"]
        XCTAssertTrue(basic.waitForExistence(timeout: 5)); basic.tap()
        let link = app.buttons["languagePriorityLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        app.revealForNavigation(link); link.tap()
        XCTAssertTrue(app.navigationBars["语言优先级"].waitForExistence(timeout: 5))
        let note = app.staticTexts["languagePriorityScreenNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        app.revealForNavigation(note)
        XCTAssertTrue(note.label.contains("操作按钮"), note.label)
        XCTAssertTrue(note.label.contains("主要内容是中文时，要整张都是中文才改译"), note.label)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "1.4.0-语言优先级说明"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
