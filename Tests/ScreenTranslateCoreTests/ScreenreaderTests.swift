import XCTest
#if canImport(ScreenTranslateCore)
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

final class ScreenreaderTests: XCTestCase {
    func testLegacyGlobalPromptMigratesToAllModesWithoutChangingProvider() throws {
        let data = Data(#"{"mode":"professional","provider":"deepSeek","customPrompt":"Keep names.","source":"ja","target":"English","configurations":{"deepSeek":{"baseURL":"https://api.deepseek.com","model":"saved-model","style":"chatCompletions"}},"accentTheme":"graphite"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        for mode in TranslationMode.allCases { XCTAssertEqual(settings.prompt(for: mode), "Keep names.") }
        XCTAssertEqual(settings.configuration.model, "saved-model")
        XCTAssertEqual(settings.mode, .professional); XCTAssertEqual(settings.source, .japanese)
        XCTAssertEqual(settings.accentTheme, .graphite, "Existing color choices survive the brand change")
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)), settings)
    }

    func testNewProfilesOverrideLegacyFieldAndEmptyDictionaryMeansReset() throws {
        for profiles in [#"{"professional":"Keep lists."}"#, "{}"] {
            let data = Data("{\"customPrompt\":\"Old global\",\"modePrompts\":\(profiles)}".utf8)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            XCTAssertEqual(settings.prompt(for: .quick), "")
            XCTAssertEqual(settings.prompt(for: .visual), "")
            XCTAssertEqual(settings.prompt(for: .professional), profiles == "{}" ? "" : "Keep lists.")
        }
    }

    func testEachModeUsesItsOwnPromptAndResetDoesNotEraseOthers() throws {
        var settings = AppSettings(); settings.target = .english
        for mode in TranslationMode.allCases { settings.setPrompt("Preference-\(mode.rawValue)", for: mode) }
        for mode in TranslationMode.allCases {
            settings.mode = mode
            let instructions = try mode == .visual ? TextPreparation.imageInstructions(settings: settings) : TextPreparation.instructions(settings: settings)
            XCTAssertTrue(instructions.contains("Preference-\(mode.rawValue)"))
            for other in TranslationMode.allCases where other != mode { XCTAssertFalse(instructions.contains("Preference-\(other.rawValue)")) }
        }
        settings.setPrompt("", for: .professional)
        XCTAssertEqual(settings.prompt(for: .professional), "")
        XCTAssertEqual(settings.prompt(for: .quick), "Preference-quick")
        XCTAssertEqual(settings.prompt(for: .visual), "Preference-visual")
        settings.translationService = .system; settings.normalizePreferences()
        XCTAssertEqual(settings.mode, .quick)
        XCTAssertEqual(settings.prompt(for: .visual), "Preference-visual")
    }

    func testCacheOnlyChangesForTheActiveModePrompt() throws {
        var settings = AppSettings()
        func key(_ settings: AppSettings) throws -> String {
            try TranslationCache.key(text: "Price: 1", settings: settings, apiKey: "test-key", readingBlocks: nil, fromImageText: true)
        }
        let original = try key(settings)
        settings.setPrompt("Keep lists.", for: .professional)
        XCTAssertEqual(try key(settings), original)
        settings.setPrompt("Keep names.", for: .quick)
        XCTAssertNotEqual(try key(settings), original)
        settings.setPrompt("", for: .quick)
        XCTAssertEqual(try key(settings), original)
    }

    func testModeExamplesAreDistinctAndUseTheChosenLanguage() {
        XCTAssertEqual(Set(TranslationMode.allCases.map { TextPreparation.promptExample(for: $0) }).count, 3)
        var settings = AppSettings(); settings.source = .japanese; settings.target = .english
        for mode in TranslationMode.allCases {
            let expanded = TextPreparation.expandedPrompt(TextPreparation.promptExample(for: mode), settings: settings)
            XCTAssertTrue(expanded.contains("English")); XCTAssertFalse(expanded.contains("{target_language}"))
        }
    }

    func testCurrencyReviewRequiresPriceContextAndTwoMatchingPixelReadings() {
        let value = line("3,98017", x: 0.65, y: 0.5, width: 0.2)
        XCTAssertFalse(OCRCurrencyReview.needsReview(value, in: [value]))
        let price = line("通常価格", x: 0.1, y: 0.5, width: 0.2)
        XCTAssertTrue(OCRCurrencyReview.needsReview(value, in: [value, price]))
        XCTAssertEqual(OCRCurrencyReview.replacement(original: "通常価格：3,98017", first: "3,980円", second: "3,980円"), "通常価格：3,980円")
        XCTAssertNil(OCRCurrencyReview.replacement(original: "3,98017", first: "¥3,980", second: "¥3,990"))
        XCTAssertNil(OCRCurrencyReview.replacement(original: "3,98017", first: "¥2,980", second: "¥2,980"))
        XCTAssertNil(OCRCurrencyReview.replacement(original: "3,98017", first: "$3,980", second: "$3,980"))
        XCTAssertNil(OCRCurrencyReview.replacement(original: "3,98017", first: "3,980", second: "3,980"))
        XCTAssertNil(OCRCurrencyReview.range(in: "A17-2046 2026/11/03 1"))
    }

    func testCurrencyDotCanBeCorrectedWithoutChangingAnyAmount() {
        XCTAssertEqual(OCRCurrencyReview.replacement(original: "·4,800", first: "¥4,800", second: "¥4,800"), "¥4,800")
        XCTAssertEqual(OCRCurrencyReview.replacement(original: "Total: ·5,600", first: "¥5,600", second: "¥5,600"), "Total: ¥5,600")
        XCTAssertNil(OCRCurrencyReview.replacement(original: "·4,800", first: "¥4,880", second: "¥4,880"))
        XCTAssertNil(OCRCurrencyReview.replacement(original: "·4,800", first: "4,800", second: "4,800"))
        XCTAssertNil(OCRCurrencyReview.replacement(original: "1", first: "¥1", second: "¥1"))
    }

    func testEnglishParagraphAndWrappedRefundBulletRemainWhole() {
        let rows = [
            line("Please arrive at 09:30; the", x: 0.05, y: 0.8, width: 0.72, height: 0.016),
            line("session starts at 10:00 and ends at 16:30.", x: 0.05, y: 0.77, width: 0.88, height: 0.022),
            line("• Request a refund before", x: 0.1, y: 0.6, width: 0.69, height: 0.018),
            line("10 October. Later requests are not accepted.", x: 0.12, y: 0.57, width: 0.79, height: 0.022)]
        let blocks = OCRLayout.readingBlocks(rows)
        XCTAssertEqual(blocks.count, 2, "\(blocks)")
        XCTAssertTrue(blocks[0].text.contains("the session starts"))
        XCTAssertEqual(blocks[1].kind, .listItem)
        XCTAssertTrue(blocks[1].text.contains("before 10 October"))
    }

    func testEmailAvatarFilteringLeavesStandaloneNumbersAndLettersElsewhere() {
        let avatar = line("E", x: 0.08, y: 0.84, width: 0.025, height: 0.025)
        let rows = [avatar, line("From:", x: 0.21, y: 0.86, width: 0.1), line("sender@example.test", x: 0.36, y: 0.86, width: 0.4),
            line("To:", x: 0.21, y: 0.83, width: 0.06), line("reader@example.test", x: 0.36, y: 0.83, width: 0.4),
            line("1", x: 0.08, y: 0.6, width: 0.025), line("E", x: 0.08, y: 0.5, width: 0.025)]
        let selected = OCRLayout.readableLines(rows, aspectRatio: 2.16)
        XCTAssertFalse(selected.contains(avatar))
        XCTAssertTrue(selected.contains { $0.text == "1" })
        XCTAssertTrue(selected.contains { $0.text == "E" && $0.y == 0.5 })
    }

    func testSlopingBilingualMenuItemKeepsItsPriceAndCaptionTogether() {
        let rows = [line("抹茶ラテ/", x: 0.34, y: 0.5, width: 0.22, height: 0.015),
            line("620円", x: 0.63, y: 0.49, width: 0.14, height: 0.022),
            line("Matcha latte", x: 0.34, y: 0.475, width: 0.25, height: 0.015),
            line("レモネード/", x: 0.34, y: 0.38, width: 0.22, height: 0.015),
            line("550円", x: 0.63, y: 0.37, width: 0.14, height: 0.022)]
        let blocks = OCRLayout.readingBlocks(rows)
        XCTAssertEqual(blocks.count, 2, "\(blocks)")
        XCTAssertEqual(blocks[0].kind, .field)
        XCTAssertTrue(blocks[0].text.contains("620円") && blocks[0].text.contains("Matcha latte"))
        XCTAssertFalse(blocks[0].text.contains("550"))
        XCTAssertEqual(blocks[0].fieldParts?.label, "抹茶ラテ / Matcha latte")
        XCTAssertEqual(blocks[0].fieldParts?.value, "620円")
        XCTAssertEqual(blocks[1].fieldParts?.value, "550円")
    }

    func testMenuSlashMisreadAsExclamationStillKeepsCaptionAndPrice() {
        let rows = [line("プリン！", x: 0.38, y: 0.275, width: 0.15, height: 0.029),
            line("480円", x: 0.66, y: 0.282, width: 0.12, height: 0.029),
            line("Custard pudding", x: 0.39, y: 0.251, width: 0.25, height: 0.031)]
        let blocks = OCRLayout.readingBlocks(rows)
        XCTAssertEqual(blocks.count, 1, "\(blocks)")
        XCTAssertEqual(blocks[0].kind, .field)
        XCTAssertTrue(blocks[0].text.contains("Custard pudding"))
        XCTAssertTrue(blocks[0].text.contains("480円"))
        XCTAssertTrue(blocks[0].text.contains("！"), "Grouping must not silently delete punctuation")
    }

    private func line(_ text: String, x: Double, y: Double, width: Double, height: Double = 0.018) -> RecognizedLine {
        .init(text: text, x: x, y: y, width: width, height: height, confidence: 1)
    }
}

final class RefinementTests: XCTestCase {
    func testFreshInstallAndAbsentPreferencesDefaultToEnglishDeepSeek() throws {
        for settings in [AppSettings(), try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))] {
            XCTAssertEqual(settings.target, .english)
            XCTAssertEqual(settings.provider, .deepSeek)
            XCTAssertEqual(settings.configuration.model, "deepseek-flash")
            XCTAssertEqual(settings.configuration.baseURL, "https://api.deepseek.com")
            XCTAssertEqual(settings.configuration.style, .chatCompletions)
        }
    }
    func testExistingProviderTargetAndModelAreNotOverwrittenByNewDefaults() throws {
        let saved = Data(#"{"provider":"openAI","target":"简体中文","configurations":{"openAI":{"baseURL":"https://api.openai.com/v1","model":"my-model","style":"responses"}}}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: saved)
        XCTAssertEqual(settings.provider, .openAI); XCTAssertEqual(settings.target, .simplifiedChinese)
        XCTAssertEqual(settings.configuration.model, "my-model")
    }
    func testChineseInterfaceLabelsDoNotLeakIntoEnglishModelInstructions() throws {
        var settings = AppSettings(); settings.source = .japanese
        XCTAssertEqual(settings.source.title, "日语"); XCTAssertEqual(settings.target.title, "英语")
        for mode in TranslationMode.allCases {
            settings.mode = mode
            let example = TextPreparation.expandedPrompt(TextPreparation.promptExample(for: mode), settings: settings)
            XCTAssertTrue(example.contains("English")); XCTAssertFalse(example.contains("英语"))
            let prompt = try mode == .visual ? TextPreparation.imageInstructions(settings: settings) : TextPreparation.instructions(settings: settings)
            XCTAssertTrue(prompt.contains("The source language is Japanese"))
        }
    }
    func testDecimalsDatesAndBareNumbersAreNeverListMarkers() {
        for value in ["1.5 kg", "1.100円", "2026.10.06", "１．５ kg", "1", "1.", "100", "-2.5°C"] {
            XCTAssertFalse(ReadingBlock.isListRow(value), value)
            XCTAssertEqual(ReadingBlock.plainText(value).first?.kind, .paragraph)
        }
        for value in ["1. Choose a drink", "１．飲み物", "2) Pay", "3、受け取り", "• Water"] {
            XCTAssertTrue(ReadingBlock.isListRow(value), value)
        }
    }
    func testMixedProseAndListsWithoutBlankLinesKeepTheirBoundaries() {
        let input = "Choose one drink:\n• Water\n• Tea\nThe price includes tax.\nNo substitutions."
        let blocks = ReadingBlock.plainText(input)
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .listItem, .listItem, .paragraph])
        XCTAssertEqual(blocks.last?.text, "The price includes tax.\nNo substitutions.")
        XCTAssertEqual(blocks.map(\.text).joined(separator: "\n"), input)
    }
    func testSemanticEmojiAreKeptWithoutExtraBullet() {
        for text in ["⚠️ Contains nuts", "⚠ Contains nuts", "✅ Paid", "☑️ Selected", "☐ Optional"] {
            XCTAssertTrue(ReadingBlock(id: 1, text: text, kind: .listItem).hasVisibleListMarker)
            XCTAssertTrue(ReadingBlock.isListRow(text))
        }
        let blocks = ReadingBlock.plainText("⚠️ Contains nuts\n✅ Paid\n☐ Optional\nThanks 👩🏽‍💻 ❤️!")
        XCTAssertEqual(blocks.map(\.kind), [.listItem, .listItem, .listItem, .paragraph])
        XCTAssertTrue(blocks.prefix(3).allSatisfy(\.hasVisibleListMarker))
        XCTAssertEqual(blocks[0].listText, "⚠️ Contains nuts")
        XCTAssertEqual(blocks.last?.text, "Thanks 👩🏽‍💻 ❤️!")
    }
    func testWhitespaceNormalizationKeepsEmojiMathAndJapanesePunctuation() {
        let text = "👨‍👩‍👧‍👦 ❤️　\r\n\r\n\r\n価格：1,100円（税別）\u{2028}1 × 2 = 2\u{2029}※対象外・ドリンクー\u{0000}"
        XCTAssertEqual(TranslationFormatting.normalized(text), "👨‍👩‍👧‍👦 ❤️\n\n価格：1,100円（税別）\n1 × 2 = 2\n\n※対象外・ドリンクー")
    }
    func testProfessionalRemovesOnlyUnrequestedWholeBlockMarkup() throws {
        let layout = ProfessionalLayout("", readingBlocks: [.init(id: 1, text: "お知らせ", kind: .heading), .init(id: 2, text: "価格：1,100円", kind: .field)])
        let result = try layout.restoreBlocks(###"{"blocks":[{"id":1,"text":"## **Notice**"},{"id":2,"text":"**Price: ¥1,100**"}]}"###)
        XCTAssertEqual(result.map(\.text), ["Notice", "Price: ¥1,100"])
        XCTAssertEqual(result.map(\.kind), [.heading, .field])
        for value in ["#topic", "2 ** 3", "**Important**", "※ 1", "★★★★★ 5"] {
            XCTAssertEqual(TranslationFormatting.professionalText(value, source: value, kind: .heading), value)
        }
        XCTAssertThrowsError(try layout.restoreBlocks(#"{"blocks":[{"id":1,"text":"Notice"},{"id":2,"text":"Price: ¥100"}]}"#))
    }
    func testSeparatorFilteringPreservesRatingsEmotionNumbersAndOperators() {
        let rows = [line("Title", 0.85), line("──────", 0.75, width: 0.8, height: 0.008),
            line("★★★★★", 0.65), line("😊", 0.55), line("1", 0.45), line("1,100円", 0.35), line("2026/10/06", 0.25), line("+", 0.15)]
        XCTAssertEqual(OCRLayout.readableLines(rows, aspectRatio: 2.16).map(\.text), ["Title", "★★★★★", "😊", "1", "1,100円", "2026/10/06", "+"])
    }
    func testTallEmojiDoesNotPromoteBodyTextToHeading() {
        let rows = [line("Details", 0.85, em: 0.03),
            line("A regular sentence.", 0.75, em: 0.016),
            line("Thanks 😊", 0.65, height: 0.036, em: 0.016),
            line("Another regular sentence.", 0.55, em: 0.016)]
        let blocks = OCRLayout.readingBlocks(rows)
        XCTAssertEqual(blocks.first?.kind, .heading)
        XCTAssertNotEqual(blocks.first(where: { $0.text.contains("Thanks") })?.kind, .heading)
    }
    func testJapanesePunctuationAndWrapsNeverGainSpaceInsideBrackets() {
        let rows = [line("Order (", 0.80), line("small)", 0.775), line(", please.", 0.75)]
        XCTAssertEqual(OCRLayout.assemble(rows), "Order (small), please.")
    }
    func testEmailHeadersDoNotGainInventedBullets() {
        let rows = [line("From: sender@example.test", 0.8), line("To: reader@example.test", 0.775), line("Subject: Your reservation", 0.75)]
        XCTAssertTrue(OCRLayout.readingBlocks(rows).allSatisfy { $0.kind != .listItem })
        XCTAssertEqual(OCRLayout.readingBlocks(rows).map(\.text), rows.map(\.text))
    }
    func testMarkupOnlyProfessionalResultIsRejected() {
        let layout = ProfessionalLayout("Notice", readingBlocks: [.init(id: 1, text: "Notice", kind: .heading)])
        XCTAssertThrowsError(try layout.restoreBlocks(#"{"blocks":[{"id":1,"text":"** **"}]}"#))
        XCTAssertEqual(TranslationFormatting.normalized("One\u{0085}Two"), "One\nTwo")
    }
    func testSymbolsAndEmailValuesAreNotEnlargedAsHeadings() {
        let rows = [line("=", 0.9, height: 0.05, em: 0.05), line("name@example.test", 0.8, height: 0.04, em: 0.04),
            line("A body sentence.", 0.6), line("Another body sentence.", 0.5)]
        for block in OCRLayout.readingBlocks(rows) where ["=", "name@example.test"].contains(block.text) {
            XCTAssertNotEqual(block.kind, .heading)
        }
    }
    func testTaxFootnoteAndBilingualSignatureKeepSeparateParagraphs() {
        let blocks = OCRLayout.readingBlocks([line("すべて税込", 0.80), line("売り切れ次第終了", 0.775),
            line("ご理解いただきありがとうございます。", 0.5), line("Event Support Team", 0.475)])
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0].text, "すべて税込")
        XCTAssertEqual(blocks.last?.text, "Event Support Team")
    }
    func testOpenTimeWithSeparatorIsAFieldNotAHeading() {
        let blocks = OCRLayout.readingBlocks([line("OPEN | 18:30", 0.8, height: 0.04, em: 0.04),
            line("Bring your ticket.", 0.6), line("No re-entry is permitted.", 0.5)])
        XCTAssertEqual(blocks[0].kind, .field)
        XCTAssertEqual(blocks[0].text, "OPEN | 18:30")
    }
    func testPunctuationAttachedToTextIsNotFilteredAsOrphanNoise() {
        let word = RecognizedLine(text: "Welcome", x: 0.1, y: 0.7, width: 0.25, height: 0.02, confidence: 1)
        let punctuation = RecognizedLine(text: "!", x: 0.36, y: 0.7, width: 0.015, height: 0.02, confidence: 1)
        let noise = RecognizedLine(text: ":!!", x: 0.05, y: 0.3, width: 0.08, height: 0.02, confidence: 0.4)
        let selected = OCRLayout.readableLines([word, punctuation, noise], aspectRatio: 2.16)
        XCTAssertEqual(selected.map(\.text), ["Welcome", "!"])
        XCTAssertEqual(OCRLayout.assemble(selected), "Welcome!")
    }
    func testMisreadMenuIconRequiresPhoneHeaderContextAndKeepsEquations() {
        let clock = RecognizedLine(text: "9:41", x: 0.1, y: 0.97, width: 0.15, height: 0.02, confidence: 1)
        let battery = RecognizedLine(text: "100", x: 0.88, y: 0.97, width: 0.07, height: 0.02, confidence: 1)
        let title = RecognizedLine(text: "Hikari Portal", x: 0.05, y: 0.895, width: 0.5, height: 0.028, confidence: 1)
        let icon = RecognizedLine(text: "=", x: 0.875, y: 0.897, width: 0.06, height: 0.027, confidence: 1)
        XCTAssertFalse(OCRLayout.readableLines([clock, battery, title, icon], aspectRatio: 2.16).contains(icon))
        XCTAssertTrue(OCRLayout.readableLines([title, icon], aspectRatio: 1).contains(icon))
        let equation = [RecognizedLine(text: "1", x: 0.8, y: 0.897, width: 0.03, height: 0.027, confidence: 1),
                        RecognizedLine(text: "1", x: 0.95, y: 0.897, width: 0.03, height: 0.027, confidence: 1)]
        XCTAssertTrue(OCRLayout.readableLines([clock, battery, title, icon] + equation, aspectRatio: 2.16).contains(icon))
    }
    private func line(_ text: String, _ y: Double, width: Double = 0.5, height: Double = 0.02, em: Double = 0.016) -> RecognizedLine {
        .init(text: text, x: 0.05, y: y, width: width, height: height, confidence: 1, glyphEm: em)
    }
}
