import XCTest
#if canImport(ScreenTranslateCore)
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

final class ImageTranslationTests: XCTestCase {
    private let box = OCRTextBox(x: 0.1, y: 0.6, width: 0.7, height: 0.1)
    private func result(_ blocks: [ReadingBlock]) -> TranslationResult {
        .init(original: "original", translated: blocks.map(\.text).joined(separator: "\n\n"),
              sourceLanguages: "英语", target: "中文", engine: "fixture", elapsed: 0, blocks: blocks)
    }

    func testOnlyExplicitCorrespondenceCanOverlayAndVisualExplanationsCannot() {
        let block = ReadingBlock(id: 1, text: "译文", original: "original", sourceBox: box)
        XCTAssertEqual(ImageTranslationLayout.items(in: result([block])).count, 1)
        XCTAssertTrue(ImageTranslationLayout.items(in: result([block, block])).isEmpty)
        var value = result([block]); value.mode = .visual
        XCTAssertTrue(ImageTranslationLayout.items(in: value).isEmpty)
        var unpaired = block; unpaired.original = nil
        XCTAssertTrue(ImageTranslationLayout.items(in: result([unpaired])).isEmpty)
    }

    func testMalformedAndOffImageGeometryIsExcludedAndEdgesAreClipped() throws {
        for invalid in [OCRTextBox(x: .nan, y: 0, width: 1, height: 1),
                        .init(x: 2, y: 0, width: 1, height: 1), .init(x: 0, y: -2, width: 1, height: 1),
                        .init(x: 0, y: 0, width: 0, height: 1)] {
            XCTAssertNil(ImageTranslationLayout.clipped(invalid))
        }
        let value = try XCTUnwrap(ImageTranslationLayout.clipped(.init(x: -0.1, y: 0.8, width: 0.4, height: 0.4)))
        XCTAssertEqual(value.x, 0); XCTAssertEqual(value.width, 0.3, accuracy: 0.0001)
        XCTAssertEqual(value.height, 0.2, accuracy: 0.0001)
    }

    func testTableCellsUseActualColumnPositionsAndSkipBlanks() {
        let cells: [OCRTextBox] = [.init(x: 0.1, y: 0.6, width: 0.2, height: 0.1),
            .init(x: 0.5, y: 0.6, width: 0.05, height: 0.1), .init(x: 0.8, y: 0.6, width: 0.15, height: 0.1)]
        let block = ReadingBlock(id: 1, text: "咖啡\t\t450 日元", kind: .tableRow,
            original: "Coffee\t\t450 yen", sourceBox: box, sourceCellBoxes: cells)
        let items = ImageTranslationLayout.items(in: result([block]))
        XCTAssertEqual(items.map(\.cell), [0, 2]); XCTAssertEqual(items.map(\.box), [cells[0], cells[2]])
        XCTAssertEqual(items.map(\.original), ["Coffee", "450 yen"])
    }

    func testVerticalDirectionIsPreservedForCJKAndEnglishUsesHorizontalText() {
        let block = ReadingBlock(id: 1, text: "译文", original: "日本語", sourceBox: box, sourceVertical: true)
        var value = result([block])
        XCTAssertEqual(ImageTranslationLayout.items(in: value).first?.vertical, true)
        value.target = "英语"
        XCTAssertEqual(ImageTranslationLayout.items(in: value).first?.vertical, false)
    }

    func testBatchRestorationKeepsGeometryWhenResponsesArriveInReverseOrder() throws {
        let sources: [ReadingBlock] = [.init(id: 4, text: "Coffee\t\t450 yen", kind: .tableRow,
            sourceBox: box, sourceCellBoxes: [box, box, box]),
            .init(id: 7, text: "Coffee", sourceBox: box, sourceVertical: true)]
        let plan = LocalImageTranslationPlan(sources)
        XCTAssertEqual(plan.requests.count, 2)
        let restored = try plan.restored([1: "450 日元", 0: "咖啡\n热饮"])
        XCTAssertEqual(restored.map(\.id), [4, 7]); XCTAssertEqual(restored[0].text, "咖啡\n热饮\t\t450 日元")
        XCTAssertEqual(restored[0].sourceCellBoxes, sources[0].sourceCellBoxes)
        XCTAssertEqual(restored[1].sourceVertical, true); XCTAssertEqual(restored[1].original, "Coffee")
        XCTAssertThrowsError(try plan.restored([0: "咖啡"]))
    }

    func testReviewKeepsVerticalAndCellMetadataAcrossHistoryEncoding() throws {
        let source = ReadingBlock(id: 1, text: "Coffee 450", sourceBox: box, sourceVertical: true)
        let translated = try ProfessionalLayout(source.text, readingBlocks: [source])
            .restoreBlocks(#"{"blocks":[{"id":1,"text":"咖啡450"}]}"#)
        let encoded = try JSONEncoder().encode(result(translated))
        let decoded = try JSONDecoder().decode(TranslationResult.self, from: encoded)
        XCTAssertEqual(TranslationReview.sourceBlocks(in: decoded).first?.sourceVertical, true)
        XCTAssertEqual(ImageTranslationLayout.items(in: decoded).first?.box, box)
    }

    func testTableOCRRetainsCellBoundsAfterGrouping() {
        let rows = [["Item", "Quantity", "Price"], ["Coffee", "2", "450"], ["Tea", "1", "300"]]
            .enumerated().map { row, cells in
                cells.enumerated().map { column, text in RecognizedLine(text: text, x: 0.1 + Double(column) * 0.3,
                    y: 0.8 - Double(row) * 0.07, width: 0.12, height: 0.025, confidence: 1) }
            }
        let grouped = OCRTableLayout.group(rows).flatMap { $0 }
        let blocks = OCRLayout.readingBlocks(grouped)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1].sourceCellBoxes?.count, 3)
        XCTAssertEqual(blocks[1].sourceCellBoxes?[2].x, 0.7)
    }

    func testMenuPriceStaysAtTheRightHandSourceLocation() throws {
        let lines: [RecognizedLine] = [
            .init(text: "Coffee", x: 0.05, y: 0.5, width: 0.2, height: 0.03, confidence: 1),
            .init(text: "450 yen", x: 0.75, y: 0.5, width: 0.2, height: 0.03, confidence: 1)]
        let sources = OCRLayout.readingBlocks(lines)
        XCTAssertEqual(sources.count, 1); XCTAssertEqual(sources[0].sourceCellBoxes?.count, 2)
        let translated = try ProfessionalLayout(sources[0].text, readingBlocks: sources)
            .restoreBlocks(#"{"blocks":[{"id":1,"text":"咖啡450日元"}]}"#)
        let items = ImageTranslationLayout.items(in: result(translated))
        XCTAssertEqual(items.map(\.text), ["咖啡", "450日元"])
        XCTAssertEqual(items.map(\.box.x), [0.05, 0.75])
    }
}
