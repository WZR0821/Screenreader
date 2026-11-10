import XCTest
#if canImport(ScreenTranslate)
@testable import ScreenTranslate
#else
@testable import ScreenTranslateCore
#endif

final class JapaneseFuriganaTests: XCTestCase {
    func testOldPreferencesDefaultOffAndChoiceRoundTrips() throws {
        let old = try JSONDecoder().decode(ReaderPreferences.self, from: Data(#"{"font":"serif","showOriginal":true}"#.utf8))
        XCTAssertFalse(old.showJapaneseFurigana)
        var updated = old; updated.showJapaneseFurigana = true
        XCTAssertEqual(try JSONDecoder().decode(ReaderPreferences.self, from: JSONEncoder().encode(updated)), updated)
        XCTAssertFalse(ReaderPreferences().showJapaneseFurigana)
    }

    func testOnlyJapaneseTargetEnablesReadings() {
        for value in ["Japanese", "日本語", "日语", "ja", "ja-JP"] { XCTAssertTrue(JapaneseFurigana.isJapanese(target: value)) }
        for value in ["中文", "简体中文", "English", "zh-Hans", ""] { XCTAssertFalse(JapaneseFurigana.isJapanese(target: value)) }
    }

    func testOkuriganaAndPrefixesStayUnannotated() {
        for (base, reading, expected) in [
            ("食べる", "たべる", ["食:た"]), ("食べ物", "たべもの", ["食:た", "物:もの"]),
            ("取り扱い", "とりあつかい", ["取:と", "扱:あつか"]),
            ("申し込む", "もうしこむ", ["申:もう", "込:こ"]),
            ("美しい", "うつくしい", ["美:うつく"]), ("お客様", "おきゃくさま", ["客様:きゃくさま"]),
            ("大人", "おとな", ["大人:おとな"])
        ] {
            let actual = JapaneseFurigana.aligned(base: base, reading: reading).map { (base as NSString).substring(with: $0.range) + ":" + $0.reading }
            XCTAssertEqual(actual, expected, base)
        }
        XCTAssertTrue(JapaneseFurigana.aligned(base: "読み", reading: "みち").isEmpty)
        XCTAssertTrue(JapaneseFurigana.aligned(base: "漢あ字", reading: "かあああな").isEmpty, "Ambiguous alignment must not attach guessed ruby")
    }

    func testActualTokenizerPreservesEmojiWhitespacePunctuationAndKana() {
        let text = "😀\t日本語を読む。\n\n今日、食べ物を食べる。 カタカナ ABC 123 <>&"
        let source = text as NSString
        let annotations = JapaneseFurigana.annotations(for: text)
        let pairs = annotations.map { source.substring(with: $0.range) + ":" + $0.reading }
        XCTAssertTrue(pairs.contains("日本語:にほんご"))
        XCTAssertTrue(pairs.contains("今日:きょう"))
        XCTAssertTrue(pairs.contains("食:た")); XCTAssertTrue(pairs.contains("物:もの"))
        var last = 0
        for value in annotations {
            XCTAssertGreaterThanOrEqual(value.range.location, last)
            XCTAssertNotNil(Range(value.range, in: text), "Never split a surrogate pair")
            XCTAssertFalse(value.reading.isEmpty)
            XCTAssertFalse(source.substring(with: value.range).contains(where: { $0.isWhitespace }))
            last = NSMaxRange(value.range)
        }
        XCTAssertEqual(JapaneseFurigana.annotations(for: text), annotations, "Cached ranges retain exact source offsets")
        XCTAssertTrue(JapaneseFurigana.annotations(for: "ひらがな カタカナ café 123 😀").isEmpty)
        let compound = "日本人形と日本人。"
        let compoundReadings = JapaneseFurigana.annotations(for: compound)
        XCTAssertFalse(compoundReadings.contains { $0.range.location == 0 && $0.reading == "にほんじん" }, "A fixed reading must not consume part of 人形")
        XCTAssertTrue(compoundReadings.contains { $0.reading == "にほんじん" && $0.range.location > 0 })
    }
}
