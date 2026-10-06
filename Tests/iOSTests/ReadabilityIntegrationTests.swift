import XCTest
import UIKit
import ImageIO
@testable import ScreenTranslate

final class ReadabilityIntegrationTests: XCTestCase {
    func testFullReaderHasOnlyReadingContentAndCollapsibleOriginal() {
        let result = TranslationResult(original: "Original: 450 yen < 500", translated: "咖啡 450 日元\n\n全文结束", sourceLanguages: "英语", target: "中文", engine: "ENGINE_SHOULD_NOT_APPEAR", elapsed: 42,
            warning: "WARNING_SHOULD_NOT_APPEAR")
        let html = String(decoding: TranslationDocument.html(result), as: UTF8.self)
        XCTAssertTrue(html.contains("咖啡 450 日元")); XCTAssertTrue(html.contains("全文结束"))
        XCTAssertTrue(html.contains("<details class=\"original\"><summary>查看原文</summary>"))
        XCTAssertTrue(html.contains("Original: 450 yen &lt; 500"))
        for unrelated in ["ENGINE_SHOULD_NOT_APPEAR", "WARNING_SHOULD_NOT_APPEAR", "WPS Office", "<aside>", "onclick=", "<script>"] {
            XCTAssertFalse(html.contains(unrelated), unrelated)
        }
        XCTAssertFalse(html.contains("position:fixed"), "Document must not cover or imitate system controls")
    }

    func testVisualSummaryDoesNotOfferPlaceholderAsOriginalText() {
        var result = TranslationResult(original: "本次直接理解图片，未生成本地 OCR 原文；图片未保存。", translated: "画面有蓝色杯子。", sourceLanguages: "图片", target: "中文", engine: "fixture", elapsed: 0)
        result.mode = .visual; result.imageMode = .visual
        let html = String(decoding: TranslationDocument.html(result), as: UTF8.self)
        XCTAssertTrue(html.contains("画面有蓝色杯子。"))
        XCTAssertFalse(html.contains("<details")); XCTAssertFalse(html.contains("未生成本地 OCR"))
    }
    func testUserMenuScreenshotPreservesDescriptionPricesQuantityAndLastOption() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "menu-screenshot", withExtension: "jpg"))
        let result = try await OCRService().recognize(Data(contentsOf: url))
        let text = result.text
        let attachment = XCTAttachment(string: text); attachment.name = "用户原图实际识字与分段"; attachment.lifetime = .keepAlways; add(attachment)
        for token in ["特製ソース", "1,100", "1,200", "1,792", "数量：1", "Pepsi", "Ginger", "Melon", "Orange Juice", "カート"] {
            XCTAssertTrue(text.localizedCaseInsensitiveContains(token), "Missing \(token): \(text)")
        }
        XCTAssertTrue(text.contains("\n\n特製ソース"), text)
        XCTAssertFalse(text.contains("23:17"), text)
        XCTAssertFalse(text.contains("1,200円1,792"), text)
    }

    func testCompleteScreenshotTravelsThroughOCRRequestAndFullDocument() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "menu-screenshot", withExtension: "jpg"))
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        let counter = RequestCounter()
        StubURLProtocol.registry.set { request in
            counter.increment()
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: Any]]
            let input = messages.last!["content"] as! String
            let document = try JSONDecoder().decode(ProfessionalLayout.Document.self, from: Data(input.utf8))
            for token in ["特製ソース", "1,100", "数量", "Pepsi", "Ginger", "Melon", "Orange Juice", "カート"] {
                XCTAssertTrue(document.blocks.contains { $0.text.contains(token) }, "Entire screen must reach API: \(token)")
            }
            // Transport fixture echoes every block; this tests completeness, not translation quality.
            let blocks = document.blocks.reversed().map { ProfessionalLayout.Block(id: $0.id, text: "译文 \($0.id)：" + $0.text) }
            let response = String(decoding: try JSONEncoder().encode(ProfessionalLayout.Document(blocks: blocks)), as: UTF8.self)
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": response]]]])
            return (200, data)
        }
        var settings = AppSettings(); settings.provider = .custom; settings.mode = .professional
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "fixture"
        let result = try await TranslationPipeline(client: APIClient(session: session)).image(Data(contentsOf: url), settings: settings, key: "fixture-key")
        XCTAssertEqual(counter.value, 1)
        let html = String(decoding: TranslationDocument.html(result, settings: settings), as: UTF8.self)
        for token in ["特製ソース", "1,100", "数量", "Pepsi", "Ginger", "Melon", "Orange Juice", "カート"] {
            XCTAssertTrue(result.translated.contains(token), token)
            XCTAssertTrue(html.contains(token), token)
        }
        XCTAssertFalse(html.contains("line-clamp")); XCTAssertFalse(html.contains("max-height"))
    }

    func testQuickOCRStillReadsMenuPricesAndLastDrink() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "menu-screenshot", withExtension: "jpg"))
        let result = try await OCRService().recognize(Data(contentsOf: url), mode: .quick)
        for token in ["1,100", "1,200", "1,792", "数量", "Pepsi", "Ginger", "Melon", "Orange Juice", "カート"] {
            XCTAssertTrue(result.text.localizedCaseInsensitiveContains(token), "Missing \(token): \(result.text)")
        }
        let attachment = XCTAttachment(string: result.text)
        attachment.name = "快速模式用户原图实际识字"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testFullDocumentRoundTripKeepsEveryParagraphAndMeaningfulNumbers() throws {
        let text = "双层芝士汉堡套餐\n\n酱汁说明。\n\n价格\n优惠价 1,100 日元\n原价 1,200 日元\n\n数量：1\n\n饮料（必选）\n零度百事可乐\n姜汁汽水\n蜜瓜汽水\n橙汁\n\n加入配送购物车"
        let result = TranslationResult(original: "", translated: text, sourceLanguages: "日语", target: "中文", engine: "fixture", elapsed: 0)
        let data = TranslationDocument.html(result)
        let restored = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
        for paragraph in text.components(separatedBy: "\n\n") { XCTAssertTrue(restored.string.contains(paragraph), restored.string) }
        XCTAssertTrue(restored.string.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("加入配送购物车"))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("width=device-width"))
    }

    func testDocumentEscapesModelMarkupAndHasNoExternalResources() {
        let result = TranslationResult(original: "", translated: "<script>alert(1)</script>\n\n价格 < 100 & 数量 > 1", sourceLanguages: "日语", target: "中文", engine: "fixture", elapsed: 0)
        let html = String(decoding: TranslationDocument.html(result), as: UTF8.self)
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("价格 &lt; 100 &amp; 数量 &gt; 1"))
        XCTAssertFalse(html.contains("src=\"http"))
        XCTAssertFalse(html.contains("<iframe"))
    }

    @MainActor private func screenshot() -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1950), format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1950))
            let font: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 34), .foregroundColor: UIColor.black]
            ("22:37" as NSString).draw(at: CGPoint(x: 45, y: 30), withAttributes: font)
            ("100" as NSString).draw(at: CGPoint(x: 785, y: 30), withAttributes: font)
            ("帖子" as NSString).draw(at: CGPoint(x: 360, y: 145), withAttributes: font)
            ("Casefinite" as NSString).draw(at: CGPoint(x: 45, y: 290), withAttributes: font)
            ("Only 16g. Price 3980 yen." as NSString).draw(at: CGPoint(x: 45, y: 420), withAttributes: font)
            ("Hello, world!" as NSString).draw(at: CGPoint(x: 45, y: 475), withAttributes: font)
        }
    }

    func testRealVisionFiltersStatusBarAndKeepsCompleteRawText() async throws {
        let data = await screenshot()
        let result = try await OCRService().recognize(data)
        XCTAssertTrue(result.rawText.contains("22:37"), result.rawText)
        XCTAssertFalse(result.text.contains("22:37"), result.text)
        XCTAssertFalse(result.text.contains("帖子"), result.text)
        XCTAssertTrue(result.text.contains("16g"), result.text)
        XCTAssertTrue(result.text.contains("3980"), result.text)
        XCTAssertTrue(result.text.contains("Casefinite"), result.text)
        XCTAssertGreaterThan(result.filteredLineCount, 0)
        let all = try await OCRService().recognize(data, cleanScreenText: false)
        XCTAssertTrue(all.text.contains("22:37"), all.text)
    }

    func testImagePreparationProducesBoundedJPEGWithoutMetadata() async throws {
        let data = await MainActor.run {
            UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1800)).pngData { ctx in
                UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 1800))
            }
        }
        let jpeg = try await ImagePreparation.jpeg(data)
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xff, 0xd8])
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual((properties[kCGImagePropertyPixelHeight] as! NSNumber).intValue, 2048)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertLessThan(jpeg.count, 2_000_000)
    }

    func testVisualModeWorksWithoutAnyOCRTextAndOnlyMakesOneRequest() async throws {
        let data = await MainActor.run {
            UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).pngData { ctx in
                UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            }
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        let counter = RequestCounter()
        StubURLProtocol.registry.set { request in
            counter.increment()
            let root = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let messages = root["messages"] as! [[String: Any]]
            XCTAssertNotNil(messages[1]["content"] as? [[String: Any]])
            return (200, Data(#"{"choices":[{"message":{"content":"画面大意：纯蓝色画面。"}}]}"#.utf8))
        }
        var settings = AppSettings(); settings.provider = .custom; settings.imageMode = .visual
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "vision"
        let result = try await TranslationPipeline(client: APIClient(session: session)).image(data, settings: settings, key: "fixture-key")
        XCTAssertEqual(result.imageMode, .visual)
        XCTAssertEqual(result.translated, "画面大意：纯蓝色画面。")
        XCTAssertEqual(counter.value, 1)
        XCTAssertNotNil(result.recognitionSeconds)
        XCTAssertEqual(result.visualOCR, false); XCTAssertTrue(result.original.isEmpty)
        XCTAssertFalse(String(decoding: TranslationDocument.html(result), as: UTF8.self).contains("<details"))
        XCTAssertNotNil(result.requestSeconds)
    }

    func testBlankImageInTextModeNeverUploadsImageAsFallback() async {
        let data = await MainActor.run {
            UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).pngData { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            }
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        StubURLProtocol.registry.set { _ in XCTFail("Text-only mode must not upload blank images"); return (200, Data()) }
        do { _ = try await TranslationPipeline(client: APIClient(session: session)).image(data, settings: AppSettings(), key: "fixture-key"); XCTFail() }
        catch { XCTAssertEqual(error as? TranslationError, .noText) }
    }
}
