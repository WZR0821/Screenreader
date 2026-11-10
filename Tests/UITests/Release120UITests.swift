import XCTest

final class Release120UITests: XCTestCase {
    private var app: XCUIApplication!
    @MainActor private func launch() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["--ui-test", "--fixture-history"]
        app.launch()
    }

    @MainActor func testCustomTypographyInSettingsPersistsAcrossTabsAndResets() {
        launch()
        openReaderSettings()
        let size = app.sliders["readerFontSizeSlider"]
        reveal(size)
        let sliderY = size.frame.minY
        size.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(size.frame.minY, sliderY, accuracy: 1, "Preview changes must not move the active slider")
        // XCTest slider drags are approximate; verify the displayed choice survives navigation.
        let chosenSize = app.staticTexts["readerFontSizeValue"].label
        XCTAssertGreaterThan(Int(chosenSize.split(separator: " ")[0]) ?? 0, 17)
        let font = app.buttons["readerFontPicker"]
        reveal(font); font.tap(); app.buttons["衬线字体"].tap()
        let weight = app.switches["readerEmphasisToggle"]
        reveal(weight); weight.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let line = app.sliders["readerLineSpacingSlider"]
        reveal(line); line.adjust(toNormalizedSliderPosition: 1)
        let chosenLine = app.staticTexts["readerLineSpacingValue"].label
        XCTAssertGreaterThan(Int(chosenLine.split(separator: " ")[0]) ?? 0, 5)
        let paragraph = app.sliders["readerParagraphSpacingSlider"]
        reveal(paragraph); paragraph.adjust(toNormalizedSliderPosition: 1)
        let chosenParagraph = app.staticTexts["readerParagraphSpacingValue"].label
        XCTAssertGreaterThan(Int(chosenParagraph.split(separator: " ")[0]) ?? 0, 14)
        attach("1.2.0-custom-spacing")
        app.tabBars.buttons["翻译"].tap()
        app.tabBars.buttons["设置"].tap()
        reveal(size)
        XCTAssertEqual(app.staticTexts["readerFontSizeValue"].label, chosenSize)
        reveal(font); XCTAssertTrue(font.label.contains("衬线字体"))
        reveal(line); XCTAssertEqual(app.staticTexts["readerLineSpacingValue"].label, chosenLine)
        reveal(paragraph); XCTAssertEqual(app.staticTexts["readerParagraphSpacingValue"].label, chosenParagraph)
        let reset = app.buttons["resetReaderPreferences"]
        reveal(reset); reset.tap()
        reveal(line); XCTAssertEqual(app.staticTexts["readerLineSpacingValue"].label, "5 pt")
        reveal(size); XCTAssertEqual(app.staticTexts["readerFontSizeValue"].label, "17 pt")
        for _ in 0..<4 { app.swipeDown() }
        attach("1.2.0-reader-preview")
    }

    @MainActor func testSpacingAndSizePresetsReplaceCustomValues() {
        launch(); openReaderSettings()
        let size = app.sliders["readerFontSizeSlider"]
        reveal(size); size.adjust(toNormalizedSliderPosition: 0.8)
        let sizes = app.segmentedControls["readerTextSizePicker"]
        reveal(sizes); sizes.buttons["较大"].tap()
        XCTAssertEqual(app.staticTexts["readerFontSizeValue"].label, "20 pt")
        let line = app.sliders["readerLineSpacingSlider"]
        reveal(line); line.adjust(toNormalizedSliderPosition: 1)
        let paragraph = app.sliders["readerParagraphSpacingSlider"]
        reveal(paragraph); paragraph.adjust(toNormalizedSliderPosition: 1)
        let spacing = app.segmentedControls["readerSpacingPicker"]
        reveal(spacing); spacing.buttons["紧凑"].tap()
        reveal(line); XCTAssertEqual(app.staticTexts["readerLineSpacingValue"].label, "2 pt")
        reveal(paragraph); XCTAssertEqual(app.staticTexts["readerParagraphSpacingValue"].label, "8 pt")
    }

    @MainActor func testAccessibilitySizeKeepsSettingsReachable() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-test", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["sourceLanguagePicker"].isHittable)
        XCTAssertTrue(app.buttons["targetLanguagePicker"].isHittable)
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settingsAccessibleScroll"].waitForExistence(timeout: 5))
        let usage = app.buttons["usageGuideLink"]
        for _ in 0..<12 where !usage.isHittable { app.swipeUp() }
        XCTAssertTrue(usage.isHittable)
        let credit = app.staticTexts["developerCredit"]
        for _ in 0..<5 where !credit.isHittable { app.swipeUp() }
        XCTAssertTrue(credit.isHittable)
        attach("1.2.0-accessibility-settings")
    }

    @MainActor private func openReaderSettings() {
        app.tabBars.buttons["设置"].tap(); app.buttons["displaySettingsLink"].tap(); app.buttons["readerSettingsLink"].tap()
    }
    @MainActor private func reveal(_ element: XCUIElement) {
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.minY > 110 && element.frame.maxY < app.frame.maxY - 100 { return }
            if element.exists && element.frame.minY < 110 { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
