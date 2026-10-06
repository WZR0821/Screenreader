import XCTest
import UIKit
import WebKit
@testable import ScreenTranslate

final class GeneratedFixtureTests: XCTestCase {
    private func image(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "png"))
        return try Data(contentsOf: url)
    }

    func testGeneratedFixturesRetainCriticalFactsAndLastContentWithRealVision() async throws {
        let cases: [(String, [String])] = [
            ("01-menu-ja-en", ["1,100", "数量：1", "ソースなし", "Ginger", "Orange", "カート"]),
            ("02-shopping-ja-en-dark", ["2,980", "3,980", "16g", "0円", "100円", "2026/10/31", "数量：2", "在庫：7", "併用できません", "Checkout"]),
            ("03-login-ja-en", ["name@example.test", "8", "表示できない場合", "メンテナンス"]),
            ("04-transit-ja-en", ["2026/10/06", "10:00", "12:30", "09:20", "13:10", "14:05", "380", "190", "特急", "View details"]),
            ("05-email-en-ja", ["12 October", "14 October 2026", "09:30", "10:00", "16:30", "Room 2", "not Room 1", "A17-2046", "not provided", "10 October", "Event Support Team"]),
            ("06-cafe-photo-ja-en", ["620", "550", "480", "税込", "売り切れ"]),
            ("07-music-poster-ja-en", ["2026/11/03", "18:30", "19:00", "2,400", "2,900", "保護者", "持ち込み", "tickets.example.test"]),
            ("08-booking-en-ja", ["A17-2046", "2026/11/03", "18:30", "Guests：3", "4,800", "800", "5,600", "未使用", "72", "再入場", "View tickets"])
        ]
        for (name, facts) in cases {
            let start = Date()
            let result = try await OCRService().recognize(image(name), source: .automatic, mode: .professional)
            for fact in facts { XCTAssertTrue(result.text.localizedCaseInsensitiveContains(fact), "\(name) lost \(fact): \(result.text)") }
            if name == "05-email-en-ja" {
                XCTAssertTrue(result.blocks.contains { $0.kind == .paragraph && $0.text.contains("09:30; the session starts at 10:00") })
                XCTAssertTrue(result.blocks.contains { $0.kind == .listItem && $0.text.contains("refund before 10 October") })
                XCTAssertFalse(result.blocks.contains { $0.text == "E" })
            }
            if name == "06-cafe-photo-ja-en" {
                for (caption, amount) in [("Matcha latte", "620円"), ("Lemonade", "550円"), ("Custard pudding", "480円")] {
                    let item = result.blocks.filter { $0.kind == .field && $0.text.contains(caption) }
                    XCTAssertEqual(item.count, 1, "\(caption) must be one item, not a duplicated caption")
                    XCTAssertTrue(item.first?.text.contains(amount) == true, "\(caption) must keep its own price")
                }
                XCTAssertFalse(result.blocks.contains { $0.kind == .paragraph && $0.text.contains("プリン") })
            }
            let data = try JSONSerialization.data(withJSONObject: ["case": name, "runtime": "iOS Simulator / Apple Vision / no API",
                "seconds": Date().timeIntervalSince(start), "rawText": result.rawText, "text": result.text,
                "refinements": result.refinementAttempts, "recovered": result.recoveredLineCount,
                "blocks": result.blocks.map { ["id": $0.id, "kind": $0.kind.rawValue, "text": $0.text] }], options: [.prettyPrinted])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "generated-\(name)-OCR"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testGeneratedQuantityAndStockAreDifferentFields() async throws {
        let result = try await OCRService().recognize(image("02-shopping-ja-en-dark"), source: .automatic, mode: .professional)
        XCTAssertTrue(result.blocks.contains { $0.kind == .field && $0.text == "数量：2" }, "\(result.blocks)")
        XCTAssertTrue(result.blocks.contains { $0.kind == .field && $0.text == "在庫：7" }, "\(result.blocks)")
        XCTAssertTrue(result.blocks.contains { $0.kind == .field && $0.text == "送料：0円" }, "\(result.blocks)")
        XCTAssertTrue(result.blocks.contains { $0.kind == .field && $0.text == "通常価格：3,980円" }, "\(result.blocks)")
        XCTAssertFalse(result.blocks.contains { $0.text.contains("Phone case") && $0.text.contains("約16g") })
        XCTAssertFalse(result.blocks.contains { $0.text.contains("数量") && $0.text.contains("在庫") })
    }

    func testGeneratedMenuAndNoticeHaveReadableHeadingAndListHierarchy() async throws {
        let menu = try await OCRService().recognize(image("01-menu-ja-en"), source: .automatic, mode: .professional)
        XCTAssertEqual(menu.blocks.filter { $0.kind == .listItem }.count, 4, "\(menu.blocks)")
        XCTAssertTrue(menu.blocks.contains { $0.kind == .heading && $0.text.contains("必須選択") }, "\(menu.blocks)")
        XCTAssertFalse(menu.blocks.contains { $0.kind == .heading && $0.text.contains("ソースなし") }, "\(menu.blocks)")
        let notice = try await OCRService().recognize(image("04-transit-ja-en"), source: .automatic, mode: .professional)
        XCTAssertFalse(notice.blocks.contains { $0.kind == .heading && $0.text.contains("見合わせ") }, "\(notice.blocks)")
        XCTAssertFalse(notice.blocks.contains { $0.kind == .heading && $0.text == "2026/10/06" }, "\(notice.blocks)")
        let booking = try await OCRService().recognize(image("08-booking-en-ja"), source: .automatic, mode: .professional)
        XCTAssertFalse(booking.blocks.contains { $0.text == "・・・" }, "\(booking.blocks)")
    }

    func testQuickModeRecoversOneMissingDarkNumericFieldWithoutGeneralReviews() async throws {
        let result = try await OCRService().recognize(image("02-shopping-ja-en-dark"), source: .automatic, mode: .quick)
        XCTAssertTrue(result.blocks.contains { $0.text == "送料：0円" }, "\(result.blocks)")
        XCTAssertLessThanOrEqual(result.refinementAttempts, 1)
        XCTAssertTrue(result.lowConfidence, "A 0.5-confidence reading must still offer image retry")
    }

    func testGeneratedTicketAndTransitTablesKeepWholeRows() async throws {
        for (name, rows) in [("08-booking-en-ja", 2), ("04-transit-ja-en", 3)] {
            let result = try await OCRService().recognize(image(name), source: .automatic, mode: .professional)
            XCTAssertEqual(result.blocks.filter { $0.kind == .tableRow }.count, rows, "\(result.blocks)")
            if name.hasPrefix("08") {
                XCTAssertTrue(result.blocks.contains { $0.text.contains("予約完了") }, "\(result.blocks)")
                XCTAssertTrue(result.blocks.contains { $0.kind == .field && $0.text == "Total paid：¥5,600" }, "\(result.blocks)")
                let table = result.blocks.filter { $0.kind == .tableRow }.compactMap(\.tableCells)
                XCTAssertTrue(table.contains { $0[0].contains("Adult") && $0[1] == "2" && $0[2].contains("4,800") }, "\(table)")
                XCTAssertTrue(table.contains { $0[0].contains("Child") && $0[1] == "1" && $0[2].contains("800") }, "\(table)")
            }
        }
    }

    func testLoginMenuIconDoesNotBecomeTranslatedContent() async throws {
        let result = try await OCRService().recognize(image("03-login-ja-en"), source: .automatic, mode: .professional)
        XCTAssertFalse(result.blocks.contains { ["=", "＝", "≡"].contains($0.text) })
        XCTAssertTrue(result.text.contains("name@example.test"))
        XCTAssertTrue(result.text.contains("8"))
        XCTAssertTrue(result.text.contains("メンテナンス"))
    }

    @MainActor func testTableReaderEscapesCellsAndKeepsColumnsAndFinalLineAtLargeSize() async throws {
        var result = TranslationResult(original: "Item\tQty\tAmount", translated: "", sourceLanguages: "英语", target: "中文", engine: "fixture", elapsed: 0)
        result.blocks = [.init(id: 1, text: "票种\t数量\t金额", kind: .tableHeader),
            .init(id: 2, text: "成人票\t2\t¥4,800", kind: .tableRow),
            .init(id: 3, text: "儿童票 <script>\t1\t¥800", kind: .tableRow),
            .init(id: 4, text: "最后一行：不可再次入场。", kind: .paragraph)]
        result.translated = result.blocks!.map(\.text).joined(separator: "\n\n")
        var settings = AppSettings(); settings.reader.textSize = .large
        let html = String(decoding: TranslationDocument.html(result, settings: settings), as: UTF8.self)
        XCTAssertTrue(html.contains("&lt;script&gt;")); XCTAssertFalse(html.contains("<script>"))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let ready = expectation(description: "Reader loaded")
        let observer = GeneratedReaderObserver { ready.fulfill() }; view.navigationDelegate = observer
        view.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [ready], timeout: 10)
        let stats = try await view.evaluateJavaScript("""
        (() => ({width:document.documentElement.scrollWidth, viewport:window.innerWidth,
          cells:[...document.querySelectorAll('tr')].map(row=>[...row.children].map(c=>c.textContent)),
          ending:document.querySelector('main').lastChild.textContent}))()
        """) as! [String: Any]
        XCTAssertLessThanOrEqual(stats["width"] as! Double, stats["viewport"] as! Double + 1)
        XCTAssertEqual((stats["cells"] as! [[String]])[1], ["成人票", "2", "¥4,800"])
        XCTAssertEqual(stats["ending"] as? String, "最后一行：不可再次入场。")
        let screenshot = try await view.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "三列表格大字体320宽排版-1.9.1"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private final class GeneratedReaderObserver: NSObject, WKNavigationDelegate {
    let didLoad: () -> Void
    init(_ didLoad: @escaping () -> Void) { self.didLoad = didLoad }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { didLoad() }
}
