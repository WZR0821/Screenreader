import XCTest
#if canImport(ScreenTranslate)
@testable import ScreenTranslate
#else
@testable import ScreenTranslateCore
#endif

final class PreferencesTests: XCTestCase {
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
            let anchor = ThemeRGB.hex(dark ? 0x2C2C2E : 0xF1F0EC)
            let backgrounds = dark ? [0x171715, 0x2C2C2E] : [0xFAF9F7, 0xF1F0EC, 0xffffff]
            for color in colors {
                let adapted = color.accessible(on: anchor)
                for background in backgrounds { XCTAssertGreaterThanOrEqual(adapted.contrast(with: .hex(background)), 4.5) }
                XCTAssertGreaterThanOrEqual(adapted.contrast(with: adapted.foreground), 4.5)
            }
        }
    }
}
