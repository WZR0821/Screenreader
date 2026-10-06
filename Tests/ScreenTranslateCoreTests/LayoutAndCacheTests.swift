import XCTest
#if canImport(ScreenTranslateCore)
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

final class LayoutAndCacheTests: XCTestCase {
    private func line(_ text: String, _ x: Double, _ y: Double, _ width: Double = 0.7, _ height: Double = 0.02) -> RecognizedLine {
        .init(text: text, x: x, y: y, width: width, height: height, confidence: 0.95)
    }

    func testGeometryKeepsMultipleHeadingsListsAndParagraphs() {
        let rows = [line("Breakfast menu", 0.06, 0.88, 0.8, 0.04),
            line("Freshly made every day.", 0.06, 0.83), line("Served until noon.", 0.06, 0.807),
            line("Drinks", 0.06, 0.70, 0.6, 0.034),
            line("Coffee", 0.06, 0.62, 0.2), line("450円", 0.75, 0.62, 0.15),
            line("Tea", 0.06, 0.56, 0.1), line("Orange juice", 0.06, 0.50, 0.28)]
        let blocks = OCRLayout.readingBlocks(rows)
        XCTAssertEqual(blocks.filter { $0.kind == .heading }.map(\.text), ["Breakfast menu", "Drinks"])
        XCTAssertTrue(blocks.contains { $0.kind == .paragraph && $0.text.contains("every day.") && $0.text.contains("until noon.") })
        XCTAssertTrue(blocks.contains { $0.kind == .field && $0.text.contains("Coffee") && $0.text.contains("450円") })
        XCTAssertTrue(blocks.contains { $0.kind == .listItem && $0.text == "Orange juice" })
    }

    func testNearbyQuantityLabelsEachOwnTheirClosestNumber() {
        let rows = [line("数量", 0.05, 0.55, 0.15), line("数量", 0.05, 0.50, 0.15),
            line("1", 0.8, 0.535, 0.03), line("2", 0.8, 0.495, 0.03)]
        let text = OCRLayout.assemble(rows)
        XCTAssertTrue(text.contains("数量：1"), text); XCTAssertTrue(text.contains("数量：2"), text)
        XCTAssertEqual(text.components(separatedBy: "数量").count, 3)
    }

    func testLargeNoticeProseAndEventTimesAreNotTurnedIntoHeadings() {
        let rows = [line("運行のお知らせ", 0.06, 0.88, 0.8, 0.04),
            line("2026/10/06", 0.06, 0.80, 0.6, 0.036),
            line("10:00～12:30", 0.06, 0.74, 0.65, 0.036),
            line("中央駅～川辺駅は運転を見合わせます。振替バスをご利用ください。", 0.06, 0.67, 0.86, 0.036),
            line("この切符では特急にご乗車いただけません。", 0.06, 0.30),
            line("最新情報は公式サイトをご確認ください。", 0.06, 0.24)]
        let blocks = OCRLayout.readingBlocks(rows)
        XCTAssertEqual(blocks.filter { $0.kind == .heading }.map(\.text), ["運行のお知らせ"])
        XCTAssertTrue(blocks.contains { $0.kind == .paragraph && $0.text.contains("振替バス") })
        XCTAssertTrue(blocks.contains { $0.kind == .field && $0.text == "10:00～12:30" })
        XCTAssertTrue(blocks.contains { $0.text.contains("特急") })
    }

    func testRequiredChoiceHeadingAndFirstOptionKeepListDespiteGlyphHeightDifference() {
        let rows = [line("ドリンク / Drinks　必須選択", 0.06, 0.80, 0.85),
            line("コーラ / Cola", 0.06, 0.70, 0.36, 0.023),
            line("ジンジャーエール / Ginger ale", 0.06, 0.62, 0.7, 0.02),
            line("メロンソーダ / Melon soda", 0.06, 0.54, 0.63, 0.02),
            line("オレンジジュース / Orange juice", 0.06, 0.46, 0.72, 0.02)]
        let blocks = OCRLayout.readingBlocks(rows)
        XCTAssertEqual(blocks.first?.kind, .heading)
        XCTAssertEqual(blocks.filter { $0.kind == .listItem }.count, 4)
    }

    func testDigitsAtEdgesDatesAndPercentagesSurvivePhoneShape() {
        var tiny = line("1", 0.96, 0.4, 0.015, 0.008); tiny.confidence = 0.2
        let rows = [line("11:24", 0.1, 0.96, 0.2), line("100", 0.82, 0.96, 0.1), tiny,
            line("2026/10/06", 0.03, 0.3), line("50%", 0.02, 0.2)]
        let values = OCRLayout.readableLines(rows, aspectRatio: 2.17).map(\.text)
        XCTAssertEqual(values, ["1", "2026/10/06", "50%"])
    }

    func testProfessionalOutputUsesSourceKindsEvenIfModelInventsThem() throws {
        let blocks: [ReadingBlock] = [.init(id: 1, text: "Menu", kind: .heading),
            .init(id: 2, text: "Coffee 450円", kind: .field), .init(id: 3, text: "Tea", kind: .listItem)]
        let layout = ProfessionalLayout("Menu\n\nCoffee 450円\n\nTea", readingBlocks: blocks)
        let output = #"{"blocks":[{"id":3,"text":"茶","kind":"heading"},{"id":2,"text":"咖啡 450日元","kind":"invented_style"},{"id":1,"text":"菜单","kind":"paragraph"}]}"#
        let restored = try layout.restoreBlocks(output)
        XCTAssertEqual(restored.map(\.kind), [.heading, .field, .listItem])
        XCTAssertEqual(restored.map(\.original), blocks.map { Optional($0.text) })
    }

    func testProfessionalRejectsMissingChangedAndSubstringNumbers() throws {
        let layout = ProfessionalLayout("数量 1\n\n价格 1,100円\n\n日期 2026/10/06")
        for output in [
            #"{"blocks":[{"id":1,"text":"数量100"},{"id":2,"text":"价格1100日元"},{"id":3,"text":"日期2026/10/06"}]}"#,
            #"{"blocks":[{"id":1,"text":"数量1"},{"id":2,"text":"价格1200日元"},{"id":3,"text":"日期2026/10/06"}]}"#,
            #"{"blocks":[{"id":1,"text":"数量1"},{"id":2,"text":"价格1100日元"},{"id":3,"text":"日期2026/10"}]}"#] {
            XCTAssertThrowsError(try layout.restore(output))
        }
        let valid = #"{"blocks":[{"id":1,"text":"数量１"},{"id":2,"text":"价格1100日元"},{"id":3,"text":"日期2026年10月06日"}]}"#
        XCTAssertNoThrow(try layout.restore(valid))
    }

    func testNegativeNumbersKeepTheirSignWhileDateHyphensRemainSeparators() throws {
        let layout = ProfessionalLayout("Temperature -10°C\n\n2026-10-06")
        XCTAssertThrowsError(try layout.restore(#"{"blocks":[{"id":1,"text":"温度10°C"},{"id":2,"text":"2026年10月06日"}]}"#))
        XCTAssertNoThrow(try layout.restore(#"{"blocks":[{"id":1,"text":"温度−10°C"},{"id":2,"text":"2026年10月06日"}]}"#))
    }

    func testEquidistantNumberIsKeptRatherThanAssignedToWrongQuantity() {
        let rows = [line("数量", 0.05, 0.55, 0.15), line("数量", 0.05, 0.51, 0.15), line("7", 0.8, 0.53, 0.03)]
        let text = OCRLayout.assemble(rows)
        XCTAssertTrue(text.contains("7")); XCTAssertFalse(text.contains("数量：7"), text)
    }

    func testRefinementCanCorrectTextButCannotReplaceQuantityOrPrice() {
        var original = line("Cofee 1,100円", 0.1, 0.5); original.confidence = 0.4
        XCTAssertTrue(OCRRefinementPolicy.accepts(original: original, replacement: "Coffee 1,100円", confidence: 0.9))
        XCTAssertFalse(OCRRefinementPolicy.accepts(original: original, replacement: "Coffee 1,200円", confidence: 0.99))
        XCTAssertFalse(OCRRefinementPolicy.accepts(original: original, replacement: "Coffee", confidence: 0.99))
        XCTAssertFalse(OCRRefinementPolicy.accepts(original: original, replacement: "Coffee 1,100円", confidence: 0.43))
        XCTAssertTrue(OCRRefinementPolicy.needsReview(original, imageHeight: 1000))
        let tiny = line("Fresh", 0.1, 0.5, 0.4, 0.01)
        XCTAssertTrue(OCRRefinementPolicy.needsReview(tiny, imageHeight: 1000))
    }

    func testPlainTextListsDoNotLoseNumbering() {
        let blocks = ReadingBlock.plainText("1. First\n2. Second\n\nBody paragraph.")
        XCTAssertEqual(blocks.map(\.kind), [.listItem, .listItem, .paragraph])
        XCTAssertEqual(blocks[0].listText, "1. First")
    }

    func testCacheExpiresEvictsLeastRecentlyUsedAndClears() async {
        let cache = TranslationCache(capacity: 2, lifetime: 10)
        let output = TranslationOutput(text: "译文", warning: nil)
        await cache.insert(output, for: "a", now: 0); await cache.insert(output, for: "b", now: 1)
        let a = await cache.value(for: "a", now: 2); XCTAssertEqual(a, output)
        await cache.insert(output, for: "c", now: 3)
        let b = await cache.value(for: "b", now: 3); XCTAssertNil(b)
        let expired = await cache.value(for: "a", now: 10); XCTAssertNil(expired)
        await cache.clear()
        let c = await cache.value(for: "c", now: 4); XCTAssertNil(c)
    }

    func testCacheByteLimitAndEmptyValues() async {
        let cache = TranslationCache(byteLimit: 20)
        await cache.insert(.init(text: String(repeating: "x", count: 100), warning: nil), for: "big")
        await cache.insert(.init(text: "", warning: nil), for: "empty")
        let big = await cache.value(for: "big"), empty = await cache.value(for: "empty")
        XCTAssertNil(big); XCTAssertNil(empty)
    }

    func testCacheIdentityIncludesTranslationInputsAndExcludesAppearance() throws {
        let settings = AppSettings()
        func key(_ value: AppSettings, _ credential: String = "key", _ blocks: [ReadingBlock]? = nil) throws -> String {
            try TranslationCache.key(text: "hello", settings: value, apiKey: credential, readingBlocks: blocks, fromImageText: true)
        }
        let original = try key(settings)
        for update: (inout AppSettings) -> Void in [
            { $0.target = .simplifiedChinese }, { $0.source = .japanese }, { $0.customPrompt = "brief" },
            { $0.glossary = "term" }, { $0.mode = .professional }, { $0.configuration.model = "other" },
            { $0.configuration.baseURL = "https://other.test" }, { $0.tone = .literal }] {
            var changed = settings; update(&changed); XCTAssertNotEqual(try key(changed), original)
        }
        XCTAssertNotEqual(try key(settings, "another-key"), original)
        XCTAssertNotEqual(try key(settings, "key", [.init(id: 1, text: "hello", kind: .heading)]), original)
        var appearance = settings; appearance.accentTheme = .blue; appearance.reader.textSize = .large
        XCTAssertEqual(try key(appearance), original)
        XCTAssertEqual(original.count, 64); XCTAssertFalse(original.contains("key"))
    }
}
