import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(ScreenTranslateCore)
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

final class Release111Tests: XCTestCase {
    private func line(_ text: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double = 0.02) -> RecognizedLine {
        .init(text: text, x: x, y: y, width: w, height: h, confidence: 0.95)
    }

    func testCriticalDateAndWrongScriptAreReviewedBeforeOrdinaryLowConfidenceText() {
        var normal = line("普通の説明です。", 0.1, 0.8, 0.5); normal.confidence = 0.2
        let title = line("Booking confirmed / 7*J5₴7", 0.1, 0.6, 0.8)
        let deadline = line("2026110106まで。", 0.1, 0.3, 0.5)
        let amount = line("·4,800", 0.7, 0.4, 0.2)
        let rows = [normal, title, deadline, amount]
        let order = rows.sorted { OCRRefinementPolicy.priority($0, in: rows, japaneseContext: true)
            < OCRRefinementPolicy.priority($1, in: rows, japaneseContext: true) }
        XCTAssertEqual(order.map(\.text), [deadline.text, title.text, amount.text, normal.text])
        XCTAssertEqual(OCRScriptReview.bilingualRange(in: title.text).map { String(title.text[$0]) }, "7*J5₴7")
        XCTAssertNil(OCRScriptReview.bilingualRange(in: "Booking / 予約完了"))
        XCTAssertNil(OCRScriptReview.bilingualRange(in: "Reference / A17-2046"))
    }

    func testRealMuseumWebParagraphKeepsWordsAcrossJapaneseWraps() {
        // Geometry from Vision on a real iPhone Safari capture of tnm.jp,
        // modules/r_free_page/index.php?id=167&lang=ja#tokuten (2026-10-07).
        let body = [
            line("会員校の学生・教職員は、本館（日本ギャラリー）、東", 0.058, 0.692, 0.871, 0.021),
            line("洋館（アジアギャラリー）、平成館1階（日本の考古）、", 0.058, 0.658, 0.875, 0.023),
            line("法隆寺宝物館（法隆寺献納宝物）の東博コレクショ", 0.058, 0.627, 0.846, 0.019),
            line("ン展を、会員期間中、何度でも無料でご覧いただけ", 0.058, 0.588, 0.850, 0.023),
            line("ます。", 0.058, 0.554, 0.100, 0.021),
            line("（注）黒田記念館はどなたでも無料でご観覧いただ", 0.058, 0.523, 0.850, 0.019),
            line("けます。", 0.058, 0.485, 0.133, 0.023)
        ]
        let rows = [line("特典", 0.404, 0.825, 0.192, 0.044),
                    line("●東博コレクション展の無料観覧", 0.05, 0.746, 0.575, 0.019)] + body
        let blocks = OCRLayout.readingBlocks(rows)
        XCTAssertEqual(blocks.count, 4, "\(blocks)")
        XCTAssertEqual(blocks.map(\.kind), [.heading, .listItem, .paragraph, .paragraph])
        XCTAssertEqual(blocks[2].text, body.prefix(5).map(\.text).joined())
        XCTAssertEqual(blocks[3].text, body.suffix(2).map(\.text).joined())
        XCTAssertTrue(OCRLayout.assemble(rows).contains("東洋館"))
        XCTAssertTrue(OCRLayout.assemble(rows).contains("コレクション展"))
    }

    func testSilentIconOCRDoesNotBecomeRequiredAndBatteryDoesNotBecomeMinutes() {
        let content = line("所要時間39分。14:53発。", 0.06, 0.7, 0.7)
        let rows = [line("14:53必", 0.11, 0.964, 0.16),
                    line("：！！！の", 0.71, 0.960, 0.11), line("39分", 0.84, 0.960, 0.08), content]
        XCTAssertEqual(OCRLayout.readableLines(rows, aspectRatio: 2796.0 / 1290), [content])
        XCTAssertEqual(OCRLayout.readableLines(rows, aspectRatio: 1.4), rows)
        let document = [rows[0], content]
        XCTAssertEqual(OCRLayout.readableLines(document, aspectRatio: 2.17), document)
    }

    func testRealContentStartingWithTimeIsKeptInTopMargin() {
        let rows = [line("14:53発車", 0.05, 0.95, 0.18), line("39分", 0.84, 0.96, 0.08)]
        XCTAssertEqual(OCRLayout.readableLines(rows, aspectRatio: 2.17), rows)
    }

    func testJapaneseOptionsAndDifferentColumnsAreNotMergedAsProse() {
        let rows = [line("ドリンク / Drinks　必須選択", 0.06, 0.8, 0.85),
                    line("ジンジャーエール / Ginger ale", 0.06, 0.7, 0.70),
                    line("オレンジジュース / Orange juice", 0.06, 0.62, 0.72)]
        XCTAssertEqual(OCRLayout.readingBlocks(rows).map(\.kind), [.heading, .listItem, .listItem])
        let columns = [line("こちらの条件が適用される場合には、", 0.03, 0.4, 0.52),
                       line("お申し込みは不要です。", 0.57, 0.365, 0.42)]
        XCTAssertEqual(OCRLayout.readingBlocks(columns).count, 2)
    }

    func testBilingualInstitutionLabelIsOneBlockWithoutConsumingBody() {
        let rows = [line("東京国立博物館", 0.158, 0.902, 0.296, 0.023),
                    line("TOKYO NATIONAL MUSEUM", 0.158, 0.890, 0.296, 0.012),
                    line("特典", 0.404, 0.825, 0.192, 0.044)]
        let blocks = OCRLayout.readingBlocks(rows)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks[0].text.contains("東京国立博物館 / TOKYO NATIONAL MUSEUM"))
    }

    func testEnglishHeadingsDoNotHideEntireParagraphsInTheWrongLanguage() {
        let wrong = "Text meaning\n" + String(repeating: "会员学校的学生和教职员工可在会员期间免费参观博物馆。", count: 5) + "\nScene\n这是一张博物馆网页截图。"
        XCTAssertThrowsError(try APIClient.validateOutputLanguage(wrong, target: .english)) {
            XCTAssertEqual($0 as? TranslationError, .unexpectedLanguage)
        }
        XCTAssertNoThrow(try APIClient.validateOutputLanguage(wrong, target: .simplifiedChinese))
        XCTAssertNoThrow(try APIClient.validateOutputLanguage("Visit 東京国立博物館 (Tokyo National Museum). Admission is 1,000 yen.", target: .english))
        XCTAssertNoThrow(try APIClient.validateOutputLanguage("東京国立博物館", target: .english))
    }
}

final class Release111RequestTests: XCTestCase {
    func testDeepSeekProfessionalAndVisionUseDocumentedLowEffortAcrossProtocols() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        for style in APIStyle.allCases {
            for mode in [TranslationMode.professional, .visual] {
                var settings = AppSettings(); settings.provider = .deepSeek; settings.mode = mode
                settings.configuration.style = style
                StubURLProtocol.registry.set { request in
                    let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
                    if style == .responses {
                        XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], "low")
                        XCTAssertNil(body["thinking"])
                        return (200, Data(#"{"output":[{"type":"message","content":[{"type":"output_text","text":"你好"}]}]}"#.utf8))
                    }
                    XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "enabled")
                    if style == .anthropicMessages {
                        XCTAssertEqual((body["output_config"] as? [String: String])?["effort"], "low")
                        XCTAssertNil(body["reasoning_effort"])
                        return (200, Data(#"{"content":[{"type":"text","text":"你好"}]}"#.utf8))
                    }
                    XCTAssertEqual(body["reasoning_effort"] as? String, "low")
                    return (200, Data(#"{"choices":[{"message":{"content":"你好"}}]}"#.utf8))
                }
                _ = try await APIClient(session: session).translate("Hello", settings: settings, apiKey: "fixture-key",
                    imageJPEG: mode == .visual ? Data("fixture".utf8) : nil)
            }
        }
    }
}
