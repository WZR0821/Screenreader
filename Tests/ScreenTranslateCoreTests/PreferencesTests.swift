import XCTest
#if canImport(ScreenTranslate)
@testable import ScreenTranslate
#else
@testable import ScreenTranslateCore
#endif

final class PreferencesTests: XCTestCase {
    func testLocalBatchTranslatesRepeatedParagraphOnceAndRestoresEveryOccurrence() throws {
        let plan = LocalTranslationPlan("\n\nCoffee\n\nTea\n\n\nCoffee\n \nTea\n\n")
        XCTAssertEqual(plan.requests.map(\.text), ["Coffee", "Tea"])
        XCTAssertEqual(plan.totalParts, 4)
        let coffee = plan.requests[0].index, tea = plan.requests[1].index
        XCTAssertEqual(plan.completedParts(responseIDs: [tea]), 2)
        XCTAssertEqual(plan.completedParts(responseIDs: [coffee, tea]), 4)
        XCTAssertEqual(try plan.restored([tea: "茶", coffee: "咖啡"]), "\n\n咖啡\n\n茶\n\n\n咖啡\n \n茶\n\n")
        XCTAssertThrowsError(try plan.restored([coffee: "咖啡"]))
        XCTAssertThrowsError(try plan.restored([coffee: "咖啡", tea: " "]))
        XCTAssertEqual(LocalTranslationPlan("Coffee\n\ncoffee").requests.count, 2, "Case differences may change meaning")
    }

    func testOlderReaderPreferencesKeepPresetsAndSavedLanguage() throws {
        let old = Data(#"{"target":"English","reader":{"textSize":"large","spacing":"relaxed","showOriginal":true}}"#.utf8)
        let value = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(value.target, .english)
        XCTAssertEqual(value.reader.fontSize, 20)
        XCTAssertEqual(value.reader.lineSpacing, 9)
        XCTAssertEqual(value.reader.paragraphSpacing, 24)
        XCTAssertEqual(value.reader.font, .system)
        XCTAssertFalse(value.reader.emphasized)
        XCTAssertTrue(value.reader.showOriginal)
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"reader":{}}"#.utf8))
        XCTAssertEqual(missing.target, .simplifiedChinese)
        XCTAssertEqual(missing.reader, ReaderPreferences())
    }

    func testCustomTypographySurvivesReloadAndBoundsUnsafeValues() throws {
        var value = AppSettings()
        value.reader = .init(font: .serif, emphasized: true, customFontSize: 23, customLineSpacing: 7, customParagraphSpacing: 19)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(value)), value)
        XCTAssertEqual(value.reader.fontSize, 23)
        XCTAssertEqual(value.reader.lineSpacing, 7)
        XCTAssertEqual(value.reader.paragraphSpacing, 19)
        let invalid = Data(#"{"reader":{"font":"unknown","customFontSize":1000,"customLineSpacing":-10,"customParagraphSpacing":1000}}"#.utf8)
        let normalized = try JSONDecoder().decode(AppSettings.self, from: invalid).reader
        XCTAssertEqual(normalized.font, .system)
        XCTAssertEqual(normalized.fontSize, 30)
        XCTAssertEqual(normalized.lineSpacing, 0)
        XCTAssertEqual(normalized.paragraphSpacing, 36)
        value.reader.customFontSize = .infinity; value.reader.customLineSpacing = .nan
        value.normalizePreferences()
        XCTAssertNil(value.reader.customFontSize); XCTAssertNil(value.reader.customLineSpacing)
        XCTAssertNoThrow(try JSONEncoder().encode(value))
    }

    func testSystemServiceNormalizesUnavailableModesAndAsking() throws {
        for mode in TranslationMode.allCases {
            var value = AppSettings(); value.translationService = .system; value.mode = mode; value.askModeInShortcuts = true
            let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(value))
            XCTAssertEqual(decoded.mode, .quick)
            XCTAssertEqual(decoded.allowedModes, [.quick]); XCTAssertFalse(decoded.askModeInShortcuts)
        }
    }

    func testMigrationPreservesExistingAPIProfessionalAndVisualUse() throws {
        for mode in ["professional", "visual"] {
            let json = Data("{\"mode\":\"\(mode)\",\"quickEngine\":\"system\"}".utf8)
            let value = try JSONDecoder().decode(AppSettings.self, from: json)
            XCTAssertEqual(value.translationService, .api)
            XCTAssertEqual(value.mode.rawValue, mode)
            XCTAssertEqual(value.historyLimit, 30)
            XCTAssertEqual(value.accentTheme, .blue)
        }
        let quick = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"mode":"quick","quickEngine":"system"}"#.utf8))
        XCTAssertEqual(quick.translationService, .system)
    }

    func testAppearanceAndReaderSurviveReloadAndNormalizeInvalidValues() throws {
        var value = AppSettings(); value.historyLimit = 100; value.appearance = .dark; value.accentTheme = .custom
        value.customAccent = .init(red: 0.33, green: 0.44, blue: 0.55)
        value.reader = .init(textSize: .large, spacing: .relaxed, showOriginal: true)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(value)), value)
        value.historyLimit = -2; value.customAccent = .init(red: 2, green: -1, blue: .infinity)
        value.normalizePreferences()
        XCTAssertEqual(value.historyLimit, 30); XCTAssertEqual(value.customAccent, .init(red: 1, green: 0, blue: 0))
    }

    func testEveryPaletteAndExtremeCustomColorHasReadableContrast() {
        let colors = AccentTheme.allCases.map(\.color) + [.hex(0), .hex(0xffffff), .hex(0xffff00), .hex(0x00ff00), .hex(0x777777)]
        for dark in [false, true] {
            let anchor = ThemeRGB.hex(dark ? 0x2C2C2E : 0xF2F2F7)
            let backgrounds = dark ? [0x000000, 0x1C1C1E, 0x2C2C2E] : [0xF2F2F7, 0xffffff]
            for color in colors {
                let adapted = color.accessible(on: anchor)
                for background in backgrounds { XCTAssertGreaterThanOrEqual(adapted.contrast(with: .hex(background)), 4.5) }
                XCTAssertGreaterThanOrEqual(adapted.contrast(with: adapted.foreground), 4.5)
            }
        }
    }
}
