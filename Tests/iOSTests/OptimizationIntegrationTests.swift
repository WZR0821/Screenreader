import XCTest
import UIKit
@testable import ScreenTranslate

final class OptimizationIntegrationTests: XCTestCase {
    @MainActor func testRealVisionKeepsInformationHeadingAndSentenceParagraphs() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1300), format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1300))
            for (text, y, size) in [("Breakfast menu", 100.0, 48.0), ("Freshly made every morning.", 200, 30),
                ("Served until noon.", 240, 30), ("Information", 480, 44), ("Order before 11:30.", 580, 30),
                ("Offer ends on 2026/10/06.", 620, 30), ("Coffee", 800, 32), ("Orange juice", 900, 32)] {
                (text as NSString).draw(at: CGPoint(x: 50, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black])
            }
        }
        let result = try await OCRService().recognize(data, source: .english, mode: .quick)
        XCTAssertTrue(result.blocks.contains { $0.text == "Information" && $0.kind == .heading }, "\(result.blocks)")
        XCTAssertTrue(result.blocks.contains { $0.text.contains("11:30") && $0.kind == .paragraph }, "\(result.blocks)")
        XCTAssertFalse(result.blocks.contains { $0.kind == .listItem && $0.text.contains("Order before") })
    }
    func testRepeatedAPITextSkipsNetworkAndChangedPromptOrDisabledCacheDoesNot() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        let counter = RequestCounter()
        StubURLProtocol.registry.set { _ in
            counter.increment()
            return (200, Data(#"{"choices":[{"message":{"content":"咖啡 450 日元"},"finish_reason":"stop"}]}"#.utf8))
        }
        var settings = AppSettings(); settings.provider = .custom
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "fixture"
        let pipeline = TranslationPipeline(client: APIClient(session: session))
        let first = try await pipeline.text("Coffee 450 yen", settings: settings, key: "fixture-key")
        let repeated = try await pipeline.text("Coffee 450 yen", settings: settings, key: "fixture-key")
        XCTAssertEqual(counter.value, 1); XCTAssertEqual(repeated.usedCache, true)
        XCTAssertEqual(repeated.translated, first.translated); XCTAssertEqual(repeated.requestSeconds, 0)
        XCTAssertNotEqual(first.id, repeated.id)
        settings.customPrompt = "Preserve names."
        let changed = try await pipeline.text("Coffee 450 yen", settings: settings, key: "fixture-key")
        XCTAssertEqual(changed.usedCache, false); XCTAssertEqual(counter.value, 2)
        settings.cacheTranslations = false
        _ = try await pipeline.text("Coffee 450 yen", settings: settings, key: "fixture-key")
        _ = try await pipeline.text("Coffee 450 yen", settings: settings, key: "fixture-key")
        XCTAssertEqual(counter.value, 4)
    }

    func testFailedOrIncompleteRequestsAreNotCached() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        let counter = RequestCounter()
        StubURLProtocol.registry.set { _ in
            counter.increment()
            return (200, Data(#"{"choices":[{"message":{"content":"部分译文"},"finish_reason":"length"}]}"#.utf8))
        }
        var settings = AppSettings(); settings.provider = .custom
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "fixture"
        let pipeline = TranslationPipeline(client: APIClient(session: session))
        for _ in 0..<2 {
            do { _ = try await pipeline.text("Hello", settings: settings, key: "fixture-key"); XCTFail() }
            catch { XCTAssertEqual(error as? TranslationError, .incompleteTranslation) }
        }
        XCTAssertEqual(counter.value, 2)
    }

    @MainActor func testRealSmallTextInvokesBoundedLocalReviewAndQuickModeSkipsIt() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 1200), format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1200))
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 38), .foregroundColor: UIColor.black]
            ("Menu" as NSString).draw(at: CGPoint(x: 40, y: 70), withAttributes: title)
            let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.darkGray]
            for index in 0..<12 {
                ("Coffee option \(index + 1) price 450 yen" as NSString).draw(at: CGPoint(x: 40, y: 200 + index * 55), withAttributes: small)
            }
        }
        let pro = try await OCRService().recognize(data, source: .english, mode: .professional)
        let quick = try await OCRService().recognize(data, source: .english, mode: .quick)
        XCTAssertGreaterThan(pro.refinementAttempts, 0); XCTAssertLessThanOrEqual(pro.refinementAttempts, 8)
        XCTAssertLessThanOrEqual(pro.recoveredLineCount, pro.refinementAttempts)
        XCTAssertEqual(quick.refinementAttempts, 0)
        XCTAssertTrue(pro.text.contains("450"), pro.text); XCTAssertFalse(pro.blocks.isEmpty)
        let log = XCTAttachment(string: "复识别区域：\(pro.refinementAttempts)，采用更高置信度：\(pro.recoveredLineCount)\n\(pro.text)")
        log.name = "局部复识别实测"; log.lifetime = .keepAlways; add(log)
    }

    @MainActor func testTypedDocumentRendersEveryHeadingListAndPriceWithoutMarkupInjection() throws {
        let blocks: [ReadingBlock] = [.init(id: 1, text: "早餐菜单", kind: .heading),
            .init(id: 2, text: "新鲜制作。", kind: .paragraph), .init(id: 3, text: "饮料", kind: .heading),
            .init(id: 4, text: "咖啡 450日元", kind: .field), .init(id: 5, text: "• 茶", kind: .listItem),
            .init(id: 6, text: "<script>橙汁</script>", kind: .listItem), .init(id: 7, text: "数量：1", kind: .field)]
        var result = TranslationResult(original: "", translated: blocks.map(\.text).joined(separator: "\n\n"),
            sourceLanguages: "日语", target: "中文", engine: "fixture", elapsed: 0)
        result.mode = .professional; result.blocks = blocks
        let html = String(decoding: TranslationDocument.html(result), as: UTF8.self)
        XCTAssertEqual(html.components(separatedBy: "<h1>").count - 1, 2)
        XCTAssertTrue(html.contains("<ul><li>茶</li><li>&lt;script&gt;橙汁&lt;/script&gt;</li></ul>"))
        XCTAssertTrue(html.contains("class=\"field-label\">数量</span>"))
        XCTAssertTrue(html.contains("class=\"field-value\">1</span>")); XCTAssertFalse(html.contains("<script>"))
        let restored = try NSAttributedString(data: TranslationDocument.html(result), options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
        for text in ["早餐菜单", "饮料", "450日元", "数量", "橙汁"] { XCTAssertTrue(restored.string.contains(text)) }
        XCTAssertNotNil(restored.string.range(of: #"数量\s*1"#, options: .regularExpression), "The column layout must keep quantity 1")
        let roundTrip = try JSONDecoder().decode(TranslationResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(roundTrip.blocks, blocks)
    }
}
