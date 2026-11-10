import XCTest
#if SWIFT_PACKAGE
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

final class TranslationReviewTests: XCTestCase {
    private let box = OCRTextBox(x: 0.1, y: 0.3, width: 0.8, height: 0.05)
    private func line(_ text: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double = 0.025) -> RecognizedLine {
        .init(text: text, x: x, y: y, width: width, height: height, confidence: 0.95)
    }
    private func result(table: Bool = false) -> TranslationResult {
        let blocks: [ReadingBlock] = [
            .init(id: 10, text: "菜单", kind: .heading, original: "Menu", sourceBox: box),
            table ? .init(id: 20, text: "\t茶\t2\t200日元\t", kind: .tableRow, original: "\tTea\t2\t200 yen\t", sourceBox: box)
                  : .init(id: 20, text: "咖啡 450日元", kind: .field, original: "Coffee 450 yen", sourceBox: box),
            .init(id: 30, text: "• 不可退款", kind: .listItem, original: "• No refunds", sourceBox: box)
        ]
        return .init(original: blocks.compactMap(\.original).joined(separator: "\n\n"), translated: blocks.map(\.text).joined(separator: "\n\n"),
                     sourceLanguages: "英语", target: "中文", engine: "previous model", elapsed: 1, mode: .professional, blocks: blocks, usedCache: true)
    }

    func testExistingBlockHistoryStillDecodesWithoutReviewMetadata() throws {
        let block = try JSONDecoder().decode(ReadingBlock.self, from: Data(#"{"id":1,"text":"译文","kind":"paragraph","original":"Source"}"#.utf8))
        XCTAssertNil(block.sourceBox); XCTAssertNil(block.reviewEngine)
        let restored = try JSONDecoder().decode(TranslationResult.self, from: JSONEncoder().encode(result()))
        XCTAssertEqual(restored, resultWithIdentity(from: restored))
        XCTAssertTrue(TranslationReview.canReview(restored, blockID: 20))
    }
    private func resultWithIdentity(from value: TranslationResult) -> TranslationResult {
        var expected = result(); expected.id = value.id; expected.date = value.date; return expected
    }

    func testWrappedJapaneseParagraphBoundsCoverEverySourceLine() throws {
        let rows = [line("こちらの条件が適用される場合には、", 0.06, 0.7, 0.85),
                    line("お申し込みは不要です。", 0.06, 0.66, 0.44)]
        let blocks = OCRLayout.readingBlocks(rows)
        XCTAssertEqual(blocks.count, 1)
        let bounds = try XCTUnwrap(blocks.first?.sourceBox)
        XCTAssertEqual(bounds.x, 0.06, accuracy: 0.00001)
        XCTAssertEqual(bounds.y, 0.66, accuracy: 0.00001)
        XCTAssertEqual(bounds.width, 0.85, accuracy: 0.00001)
        XCTAssertEqual(bounds.height, 0.065, accuracy: 0.00001)
    }

    func testTableRowBoundsIncludeAllColumnsAndWrappedCell() throws {
        var rows: [RecognizedLine] = []
        for (row, cells) in [["Item", "Quantity", "Price"], ["Tea", "2", "200 yen"], ["Coffee", "1", "300 yen"]].enumerated() {
            for (column, cell) in cells.enumerated() {
                rows.append(line(cell, 0.05 + Double(column) * 0.3, 0.8 - Double(row) * 0.1, 0.15))
            }
        }
        rows.append(line("unsweetened", 0.05, 0.655, 0.15))
        let block = try XCTUnwrap(OCRLayout.readingBlocks(rows).first { $0.kind == .tableRow })
        let bounds = try XCTUnwrap(block.sourceBox)
        XCTAssertTrue(block.text.contains("unsweetened"))
        XCTAssertEqual(bounds.x, 0.05, accuracy: 0.00001)
        XCTAssertEqual(bounds.width, 0.75, accuracy: 0.00001)
        XCTAssertLessThanOrEqual(bounds.y, 0.655)
        XCTAssertGreaterThanOrEqual(bounds.y + bounds.height, 0.725 - 0.00001)
    }

    func testVerticalColumnsKeepSeparateSourceCrops() throws {
        let right = RecognizedLine(text: "日本語の右列", x: 0.8, y: 0.3, width: 0.04, height: 0.5, confidence: 0.9, vertical: true)
        let left = RecognizedLine(text: "次に左の列", x: 0.6, y: 0.35, width: 0.04, height: 0.5, confidence: 0.9, vertical: true)
        let blocks = OCRLayout.readingBlocks([left, right])
        XCTAssertEqual(blocks.map { $0.sourceBox?.x }, [0.8, 0.6])
    }

    func testLocalBoundsSurviveTranslationButNeverReachAPI() throws {
        let source = ReadingBlock(id: 99, text: "Coffee 450 yen", kind: .field, sourceBox: box)
        let layout = ProfessionalLayout(source.text, readingBlocks: [source])
        let request = try layout.requestText()
        XCTAssertFalse(request.contains("sourceBox")); XCTAssertFalse(request.contains("width"))
        let restored = try layout.restoreBlocks(#"{"blocks":[{"id":1,"text":"咖啡 450日元","kind":"heading"}]}"#)
        XCTAssertEqual(restored[0].sourceBox, box); XCTAssertEqual(restored[0].kind, .field)
    }

    func testRevisionOnlyReplacesSelectedBlockAndKeepsIdentityAndLayout() throws {
        let before = result()
        let source = try TranslationReview.sourceBlock(in: before, blockID: 20, correctedText: "Coffee 460 yen")
        let replacement = ReadingBlock(id: 20, text: "咖啡 460日元", kind: source.kind, original: source.text,
            sourceBox: source.sourceBox, reviewEngine: "new model", reviewSeconds: 0.5)
        let after = try TranslationReview.replacing(in: before, blockID: 20, with: replacement)
        XCTAssertEqual(after.id, before.id); XCTAssertEqual(after.date, before.date)
        XCTAssertEqual(after.blocks?[0], before.blocks?[0]); XCTAssertEqual(after.blocks?[2], before.blocks?[2])
        XCTAssertEqual(after.blocks?.map(\.id), [10, 20, 30])
        XCTAssertEqual(after.blocks?[1].kind, .field); XCTAssertEqual(after.blocks?[1].sourceBox, box)
        XCTAssertTrue(after.original.contains("460")); XCTAssertFalse(after.original.contains("450"))
        XCTAssertTrue(after.translated.contains("460")); XCTAssertFalse(after.translated.contains("450"))
        XCTAssertEqual(after.usedCache, false)
        XCTAssertTrue(TranslationReview.sourceBlocks(in: after).allSatisfy { $0.original == nil && $0.reviewEngine == nil })
    }

    func testEditedTableRetainsOuterEmptyColumnsAndChecksNewAmountsPerCell() throws {
        let before = result(table: true)
        let source = try TranslationReview.sourceBlock(in: before, blockID: 20, correctedText: "\tTea\t3\t300 yen\t")
        XCTAssertEqual(source.tableCells, ["", "Tea", "3", "300 yen", ""])
        let good = ReadingBlock(id: 20, text: "\t茶\t3\t300日元\t", kind: .tableRow, original: source.text, sourceBox: box)
        let after = try TranslationReview.replacing(in: before, blockID: 20, with: good)
        XCTAssertEqual(after.blocks?[1].tableCells, ["", "茶", "3", "300日元", ""])
        for text in ["\t茶\t300日元\t3\t", "0\t茶\t3\t300日元\t", "\t茶\t2\t200日元\t"] {
            var bad = good; bad.text = text
            XCTAssertThrowsError(try TranslationReview.replacing(in: before, blockID: 20, with: bad))
        }
        XCTAssertThrowsError(try TranslationReview.sourceBlock(in: before, blockID: 20, correctedText: "Tea\t3\t300 yen")) {
            XCTAssertEqual($0 as? TranslationError, .reviewColumns)
        }
    }

    func testReviewKeepsSavedTargetWhenCurrentLanguageOrServiceChanges() throws {
        var current = AppSettings(); current.target = .japanese; current.translationService = .system; current.source = .japanese
        let settings = try TranslationReview.settings(for: result(), using: current)
        XCTAssertEqual(settings.target, .simplifiedChinese); XCTAssertEqual(settings.mode, .professional)
        XCTAssertEqual(settings.translationService, .api); XCTAssertEqual(settings.source, .english)
        XCTAssertEqual(current.target, .japanese); XCTAssertEqual(current.translationService, .system)
    }

    func testMissingOriginalVisualOrDuplicateIDsCannotBeReviewed() {
        var value = result(); value.blocks?[1].original = nil
        XCTAssertFalse(TranslationReview.canReview(value, blockID: 20))
        value = result(); value.mode = .visual
        XCTAssertFalse(TranslationReview.canReview(value, blockID: 20))
        value = result(); value.blocks?[2].id = 20
        XCTAssertFalse(TranslationReview.canReview(value, blockID: 20))
        XCTAssertFalse(TranslationReview.canReview(result(), blockID: 777))
    }
}
