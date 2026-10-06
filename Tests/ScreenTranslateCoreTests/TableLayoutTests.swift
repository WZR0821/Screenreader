import XCTest
#if canImport(ScreenTranslateCore)
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

final class TableLayoutTests: XCTestCase {
    private func line(_ text: String, _ x: Double, _ y: Double, _ width: Double = 0.12, _ height: Double = 0.02) -> RecognizedLine {
        .init(text: text, x: x, y: y, width: width, height: height, confidence: 1)
    }

    func testQuantityCannotConsumeStockAcrossTheNextLabel() {
        let blocks = OCRLayout.readingBlocks([line("数量", 0.06, 0.10, 0.07), line("2", 0.33, 0.10, 0.03),
            line("+", 0.43, 0.10, 0.04), line("在庫", 0.62, 0.10, 0.07), line("7", 0.80, 0.10, 0.03)])
        XCTAssertTrue(blocks.contains { $0.text == "数量：2" && $0.kind == .field }, "\(blocks)")
        XCTAssertTrue(blocks.contains { $0.text == "在庫：7" && $0.kind == .field }, "\(blocks)")
        XCTAssertFalse(blocks.contains { $0.text.contains("数量") && $0.text.contains("7") })
    }

    func testFormLabelsUseTheirOwnNearbyValue() {
        let blocks = OCRLayout.readingBlocks([line("重量", 0.06, 0.3), line("16g", 0.85, 0.3),
            line("送料", 0.06, 0.23), line("0円", 0.85, 0.23),
            line("Date", 0.06, 0.15), line("2026/11/03", 0.75, 0.15, 0.2)])
        for value in ["重量：16g", "送料：0円", "Date：2026/11/03"] {
            XCTAssertTrue(blocks.contains { $0.text == value && $0.kind == .field }, "\(blocks)")
        }
    }

    func testTicketRowsKeepQuantityAndAmountInSeparateColumns() {
        let lines = [line("Item", 0.07, 0.6), line("Qty", 0.55, 0.6, 0.07), line("Amount", 0.78, 0.6),
            line("Adult ticket", 0.07, 0.54, 0.22), line("2", 0.57, 0.54, 0.03), line("¥4,800", 0.81, 0.54),
            line("Child ticket", 0.07, 0.48, 0.22), line("1", 0.57, 0.48, 0.03), line("¥800", 0.84, 0.48, 0.09)]
        let blocks = OCRLayout.readingBlocks(lines)
        XCTAssertEqual(blocks.map(\.kind), [.tableHeader, .tableRow, .tableRow])
        XCTAssertEqual(blocks[1].tableCells, ["Adult ticket", "2", "¥4,800"])
        XCTAssertEqual(blocks[2].tableCells, ["Child ticket", "1", "¥800"])
    }

    func testRouteNamesAloneDoNotBecomeTableCells() {
        let blocks = OCRLayout.readingBlocks([line("青葉駅", 0.04, 0.6), line("中央駅", 0.30, 0.6),
            line("川辺駅", 0.58, 0.6), line("緑川駅", 0.84, 0.6)])
        XCTAssertFalse(blocks.contains { $0.tableCells != nil })
        XCTAssertEqual(blocks.count, 4)
    }

    func testBilingualTableHeadersRemainOneHeaderAndAdultChildPricesKeepTheirLabels() {
        let table = [line("発車", 0.07, 0.60), line("ホーム", 0.46, 0.60), line("行先", 0.76, 0.60),
            line("Departure", 0.07, 0.576), line("Platform", 0.46, 0.576), line("Destination", 0.76, 0.576),
            line("09:20", 0.07, 0.53), line("1", 0.50, 0.53, 0.03), line("緑川", 0.79, 0.53, 0.08),
            line("13:10", 0.07, 0.48), line("2", 0.50, 0.48, 0.03), line("森町", 0.79, 0.48, 0.08)]
        let blocks = OCRLayout.readingBlocks(table)
        XCTAssertEqual(blocks.map(\.kind), [.tableHeader, .tableRow, .tableRow])
        XCTAssertEqual(blocks[0].tableCells, ["発車 / Departure", "ホーム / Platform", "行先 / Destination"])
        let prices = OCRLayout.readingBlocks([line("大人", 0.1, 0.3), line("380円", 0.1, 0.275),
            line("子供", 0.65, 0.3), line("190円", 0.65, 0.275)])
        XCTAssertEqual(prices.map(\.text), ["大人：380円", "子供：190円"])
        XCTAssertEqual(ReadingBlock(id: 1, text: "运费：0日元", kind: .field).fieldParts?.value, "0日元")
        XCTAssertNil(ReadingBlock(id: 1, text: "注意：请在当天使用", kind: .field).fieldParts)
    }

    func testProfessionalProtocolRejectsMovingNumbersBetweenColumns() throws {
        let block = ReadingBlock(id: 1, text: "Adult ticket\t2\t¥4,800", kind: .tableRow)
        let layout = ProfessionalLayout(block.text, readingBlocks: [block])
        let valid = #"{"blocks":[{"id":1,"text":"成人票\t2\t¥4,800"}]}"#
        XCTAssertEqual(try layout.restoreBlocks(valid)[0].tableCells, ["成人票", "2", "¥4,800"])
        for output in [#"{"blocks":[{"id":1,"text":"成人票\t4,800\t¥2"}]}"#,
                       #"{"blocks":[{"id":1,"text":"成人票2张，合计¥4,800"}]}"#] {
            XCTAssertThrowsError(try layout.restoreBlocks(output))
        }
    }

    func testWrappedBulletKeepsItsConditionInTheSameBlock() {
        let blocks = OCRLayout.readingBlocks([line("• Lunch is not provided. Water will", 0.08, 0.5, 0.80),
            line("be available.", 0.10, 0.475, 0.30),
            line("• Refunds must be requested before 10 October.", 0.08, 0.42, 0.82)])
        XCTAssertEqual(blocks[0].kind, .listItem)
        XCTAssertTrue(blocks[0].text.contains("Water will be available."), "\(blocks)")
        XCTAssertEqual(blocks.count, 2)
    }

    func testBilingualProductLabelDoesNotConsumeItsDescription() {
        let blocks = OCRLayout.readingBlocks([line("スマートフォン用ケース ／ Phone case", 0.04, 0.445, 0.60, 0.019),
            line("約16gの軽量設計。背面を覆わないバンパータイプ。", 0.04, 0.418, 0.71, 0.019)])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].text, "スマートフォン用ケース ／ Phone case")
        XCTAssertTrue(blocks[1].text.hasPrefix("約16g"))
    }

    func testQuantityControlsAreRemovedButMathAndNumbersRemain() {
        let quantity = [line("数量", 0.06, 0.3, 0.07), line("1", 0.5, 0.3, 0.03), line("+", 0.65, 0.3, 0.03)]
        XCTAssertEqual(OCRLayout.readableLines(quantity, aspectRatio: 2.2).map(\.text), ["数量", "1"])
        let math = [line("1", 0.1, 0.3, 0.03), line("+", 0.2, 0.3, 0.03), line("2", 0.3, 0.3, 0.03), line("=", 0.4, 0.3, 0.03)]
        XCTAssertEqual(OCRLayout.readableLines(math, aspectRatio: 2.2), math)
        let multiplication = [line("1", 0.1, 0.3, 0.03), line("×", 0.2, 0.3, 0.03), line("2", 0.3, 0.3, 0.03)]
        XCTAssertEqual(OCRLayout.readableLines(multiplication, aspectRatio: 2.2), multiplication)
        let route = [line("中央", 0.1, 0.3), line("→", 0.4, 0.3, 0.03), line("川辺", 0.6, 0.3)]
        XCTAssertEqual(OCRLayout.readableLines(route, aspectRatio: 2.2), route)
    }

    func testJapaneseScriptReviewNeedsTwoMatchingPixelReadings() {
        XCTAssertEqual(OCRScriptReview.replacement(original: "Booking confirmed / 7*75₴7", first: "Booking confirmed / 予約完了", second: "Booking confirmed / 予約完了"), "Booking confirmed / 予約完了")
        XCTAssertNil(OCRScriptReview.replacement(original: "Booking confirmed / 7*75₴7", first: "Booking confirmed / 予約完了", second: "Booking confirmed / 予約変更"))
        XCTAssertEqual(OCRScriptReview.replacement(original: "·4,800", first: "¥4,800", second: "¥4,800"), "¥4,800")
        XCTAssertNil(OCRScriptReview.replacement(original: "·4,800", first: "¥4,900", second: "¥4,900"))
        XCTAssertFalse(OCRScriptReview.needsReview("A17-2046"))
        XCTAssertFalse(OCRScriptReview.needsReview("450円（税込）"))
        XCTAssertEqual(OCRScriptReview.replacement(original: "Booking confirmed / 7*J5₴7", first: "Booking confirmed / 予約完了", second: "Booking confirmed / 予約完了"), "Booking confirmed / 予約完了")
        XCTAssertEqual(OCRScriptReview.replacement(original: "*5,600", first: "¥5,600", second: "¥5,600"), "¥5,600")
    }

    func testEmptyNumericFieldRetryIsBoundedByTheNextLabelAndExcludesOtherRows() {
        let labels = [line("数量", 0.06, 0.30, 0.07), line("在庫", 0.62, 0.30, 0.07), line("7", 0.80, 0.30, 0.03),
            line("送料", 0.06, 0.50, 0.07), line("100円引き", 0.30, 0.44, 0.2)]
        let regions = OCRFieldReview.regions(in: labels)
        XCTAssertEqual(regions.count, 2)
        XCTAssertLessThan(regions[0].x + regions[0].width, 0.62)
        XCTAssertGreaterThan(regions[1].y, 0.46)
        XCTAssertEqual(OCRFieldReview.agreedValue("０ 円", "0円"), "0円")
        XCTAssertNil(OCRFieldReview.agreedValue("0円", "100円"))
        XCTAssertNil(OCRFieldReview.agreedValue("送料", "送料"))
        XCTAssertTrue(OCRFieldReview.regions(in: [line("Shipping", 0.06, 0.5), line("Free", 0.8, 0.5)]).isEmpty)
    }
}
