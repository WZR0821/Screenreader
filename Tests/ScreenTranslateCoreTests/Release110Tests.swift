import XCTest
#if SWIFT_PACKAGE
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

final class Release110Tests: XCTestCase {
    private func line(_ text: String, _ x: Double, _ y: Double, width: Double = 0.10) -> RecognizedLine {
        .init(text: text, x: x, y: y, width: width, height: 0.025, confidence: 0.95)
    }

    func testFiveColumnTableRetainsBlankCellAndWrappedName() {
        var lines: [RecognizedLine] = []
        for (row, cells) in [["商品", "数量", "単価", "税率", "小計"],
                             ["お茶", "2", "100円", "", "200円"],
                             ["コーヒー", "1", "300円", "10%", "300円"]].enumerated() {
            for (column, cell) in cells.enumerated() where !cell.isEmpty {
                lines.append(line(cell, 0.05 + Double(column) * 0.19, 0.80 - Double(row) * 0.1))
            }
        }
        lines.append(line("無糖", 0.05, 0.655))
        let blocks = OCRLayout.readingBlocks(lines)
        XCTAssertEqual(blocks.map(\.kind), [.tableHeader, .tableRow, .tableRow])
        XCTAssertEqual(blocks[1].tableCells, ["お茶 無糖", "2", "100円", "", "200円"])
        XCTAssertEqual(blocks[2].tableCells?.count, 5)
    }

    func testVerticalColumnsReadRightToLeftAndPreserveHorizontalHeading() {
        let right = RecognizedLine(text: "日本語の右列", x: 0.8, y: 0.3, width: 0.04, height: 0.5, confidence: 0.8, vertical: true)
        let left = RecognizedLine(text: "次に左の列", x: 0.6, y: 0.35, width: 0.04, height: 0.5, confidence: 0.8, vertical: true)
        let blocks = OCRLayout.readingBlocks([left, line("見出し", 0.1, 0.94), right])
        XCTAssertEqual(blocks.map(\.text), ["見出し", "日本語の右列", "次に左の列"])
    }

    func testReviewCoversSmallConfidentTextAndVerticalGlyphSize() {
        var small = line("税込", 0.1, 0.4); small.height = 0.01
        var vertical = line("ご予約", 0.8, 0.2, width: 0.01); vertical.vertical = true; vertical.height = 0.3
        let items = OCRReview.items([small, vertical], imageWidth: 1000, imageHeight: 1000, japanese: true)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.reasons.contains("文字较小") })
        XCTAssertTrue(items[1].reasons.contains("竖排阅读顺序与标点"))
    }

    func testLocalBatchRestoresOutOfOrderParagraphsAndRejectsMissingText() throws {
        let plan = LocalTranslationPlan("First\n\nSecond\n\n\nThird")
        XCTAssertEqual(try plan.restored([2: "三", 0: "一", 1: "二"]), "一\n\n二\n\n\n三")
        XCTAssertThrowsError(try plan.restored([0: "一", 2: "三"]))
        XCTAssertThrowsError(try plan.restored([0: "一", 1: " ", 2: "三"]))
    }

    func testProfessionalTranslationPreservesEmptyOuterCellsAndRejectsInventedValues() throws {
        let row = ReadingBlock(id: 1, text: "\tお茶\t2\t200円\t", kind: .tableRow)
        let layout = ProfessionalLayout(row.text, readingBlocks: [row])
        let output = #"{"blocks":[{"id":1,"text":"\t茶\t2\t200日元\t"}]}"#
        XCTAssertEqual(try layout.restoreBlocks(output)[0].tableCells, ["", "茶", "2", "200日元", ""])
        for invalid in [#"{"blocks":[{"id":1,"text":"茶\t2\t200日元"}]}"#,
                        #"{"blocks":[{"id":1,"text":"0\t茶\t2\t200日元\t"}]}"#,
                        #"{"blocks":[{"id":1,"text":"\t\t2\t200日元\t"}]}"#] {
            XCTAssertThrowsError(try layout.restoreBlocks(invalid))
        }
        var source = line(row.text, 0.1, 0.5, width: 0.8); source.readingKind = .tableRow
        XCTAssertEqual(OCRLayout.readingBlocks([source])[0].tableCells?.count, 5)
    }

    func testLocalCacheIgnoresAPIOnlySettingsButKeepsLanguageDirection() throws {
        var settings = AppSettings()
        func key(_ value: AppSettings) throws -> String {
            try TranslationCache.key(text: "hello", settings: value, apiKey: "", readingBlocks: nil, fromImageText: false, engine: "AppleTranslation")
        }
        let original = try key(settings)
        settings.provider = .custom; settings.glossary = "unrelated"; settings.customPrompt = "different"; settings.tone = .literal
        XCTAssertEqual(try key(settings), original)
        settings.target = .japanese
        XCTAssertNotEqual(try key(settings), original)
    }

    func testClearingCacheRejectsLateRequestAndReportsFreshStatistics() async {
        let cache = TranslationCache()
        let token = await cache.generationToken()
        await cache.clear()
        await cache.insert(.init(text: "late", warning: nil), for: "old", generation: token)
        let old = await cache.value(for: "old")
        XCTAssertNil(old)
        await cache.insert(.init(text: "fresh", warning: nil), for: "new")
        _ = await cache.value(for: "new")
        let stats = await cache.statistics()
        XCTAssertEqual(stats.count, 1); XCTAssertEqual(stats.hits, 1); XCTAssertEqual(stats.misses, 1)
    }
}
