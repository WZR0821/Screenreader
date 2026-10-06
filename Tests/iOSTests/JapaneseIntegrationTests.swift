import XCTest
import UIKit
import ImageIO
import WebKit
@testable import ScreenTranslate

final class JapaneseIntegrationTests: XCTestCase {
    @MainActor private func menuImage() -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1900), format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1900))
            func text(_ value: String, _ x: Double, _ y: Double, _ size: Double) {
                (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black])
            }
            text("ランチメニュー / Lunch menu", 45, 100, 44)
            text("いずれかを抜く場合、ソースなしになります。", 45, 200, 26)
            text("あらかじめご了承ください。", 45, 240, 26)
            text("税込価格", 45, 340, 28); text("1,100円", 650, 340, 28)
            text("ドリンク（必須選択）", 45, 470, 36)
            text("コーヒー / Coffee", 45, 570, 30); text("450円", 710, 570, 30)
            text("紅茶 / Tea", 45, 660, 30); text("400円", 710, 660, 30)
            text("数量", 45, 800, 30); text("1", 760, 800, 30)
            text("ご利用条件", 45, 970, 36)
            text("会員のみ利用可能。", 45, 1070, 26)
            text("2026/10/06まで。", 45, 1110, 26)
            text("クーポンは併用できません。", 45, 1150, 26)
            text("カートに追加する", 45, 1580, 32)
        }
    }

    func testJapaneseAndEnglishMenuOCRKeepsPricesConditionsAndLastButton() async throws {
        let data = await menuImage()
        let recognized = try await OCRService().recognize(data, source: .japanese, mode: .professional)
        for token in ["Lunch menu", "ソースなし", "税込", "1,100", "必須選択", "Coffee", "450", "Tea", "400", "数量：1", "会員のみ", "2026/10/06", "併用できません", "追加"] {
            XCTAssertTrue(recognized.text.localizedCaseInsensitiveContains(token), "Missing \(token): \(recognized.text)")
        }
        XCTAssertTrue(recognized.blocks.contains { $0.kind == .heading && $0.text.contains("ランチ") })
        XCTAssertTrue(recognized.blocks.contains { $0.kind == .heading && $0.text.contains("ドリンク") }, "\(recognized.blocks)")
        XCTAssertTrue(recognized.blocks.contains { $0.kind == .heading && $0.text.contains("ご利用条件") }, "\(recognized.blocks)")
        XCTAssertTrue(recognized.blocks.contains { $0.kind == .field && $0.text.contains("Coffee") && $0.text.contains("450") })
        XCTAssertFalse(recognized.blocks.contains { $0.text.contains("Coffee") && $0.text.contains("400") })
        if recognized.rawText.contains("2026110106") { XCTAssertGreaterThan(recognized.recoveredLineCount, 0) }
        let attachment = XCTAttachment(string: recognized.blocks.map { "\($0.kind.rawValue): \($0.text)" }.joined(separator: "\n\n"))
        attachment.name = "日英菜单真实OCR-1.9"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testJapaneseKanaLabelsAreNotMisidentifiedAsUnrelatedLanguages() {
        let language = LanguageDetector.describe("ログイン\n\nIDを入力してください。\n\nパスワード")
        XCTAssertTrue(language.contains("日语"), language)
        XCTAssertFalse(language.contains("Hungarian"), language)
    }

    func testShortBrandsDatesAndCountsDoNotInventExtraLanguages() {
        let language = LanguageDetector.describe("AIR SHELL\n\nスマートフォン用ケース\n\n通常価格：3,980円\n\n数量：2\n\n在庫：7\n\n2026/10/31")
        XCTAssertTrue(language.contains("日语"), language)
        XCTAssertFalse(language.contains("Indonesian"), language)
        XCTAssertFalse(language.contains("中文"), language)
        XCTAssertEqual(LanguageDetector.describe("A17-2046\n\n2026/11/03\n\n18:30\n\n7"), "自动识别")
    }

    func testTallMenuHasTwoPixelOnlyDetailsAndRetainsBottomText() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "menu-screenshot", withExtension: "jpg"))
        let prepared = try await ImagePreparation.vision(Data(contentsOf: url))
        XCTAssertEqual(prepared.details.count, 2)
        for (index, data) in ([prepared.overview] + prepared.details).enumerated() {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            let width = (properties[kCGImagePropertyPixelWidth] as! NSNumber).intValue
            let height = (properties[kCGImagePropertyPixelHeight] as! NSNumber).intValue
            XCTAssertLessThanOrEqual(max(width, height), index == 0 ? 2048 : 1800)
            XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
            // ImageIO may generate dimensions/colour-space EXIF during encoding;
            // no original camera, timestamp or location metadata is copied.
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            for key in [kCGImagePropertyExifDateTimeOriginal, kCGImagePropertyExifUserComment, kCGImagePropertyExifLensModel] { XCTAssertNil(exif[key]) }
        }
        let lower = try await OCRService().recognize(prepared.details[1], source: .japanese, mode: .visual)
        XCTAssertTrue(lower.text.contains("Orange Juice"), lower.text)
        XCTAssertTrue(lower.text.contains("カート"), lower.text)
        let upper = try await OCRService().recognize(prepared.details[0], source: .japanese, mode: .visual)
        XCTAssertTrue(upper.text.contains("特製ソース"), upper.text)
        XCTAssertTrue(upper.text.contains("1,100"), upper.text)
    }

    func testVisualMenuIncludesReferenceAndAllImagesInOneAPICall() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "menu-screenshot", withExtension: "jpg"))
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        let counter = RequestCounter()
        StubURLProtocol.registry.set { request in
            counter.increment()
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: Any]]
            let content = messages.last!["content"] as! [[String: Any]]
            XCTAssertEqual(content.filter { $0["type"] as? String == "image_url" }.count, 3)
            let reference = try XCTUnwrap(content.first?["text"] as? String)
            for token in ["特製ソース", "1,100", "Orange Juice", "カート"] { XCTAssertTrue(reference.contains(token), reference) }
            let text = "文字大意\n双层芝士汉堡套餐，优惠价 1,100 日元，数量 1。\n• 零度百事可乐\n• 姜汁汽水\n• 蜜瓜汽水\n• 橙汁\n\n如需去除其中任一种配料，将不加酱汁。\n\n画面大意\n餐饮下单页面，上方有汉堡照片，下方选择饮料并加入购物车。"
            return (200, try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text], "finish_reason": "stop"]]]))
        }
        var settings = AppSettings(); settings.provider = .custom; settings.mode = .visual; settings.source = .japanese; settings.target = .simplifiedChinese
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "vision"
        let result = try await TranslationPipeline(client: APIClient(session: session)).image(Data(contentsOf: url), settings: settings, key: "fixture-key")
        XCTAssertEqual(counter.value, 1); XCTAssertEqual(result.visualOCR, true)
        XCTAssertTrue(result.original.contains("特製ソース"))
        XCTAssertEqual(result.blocks?.filter { $0.kind == .heading }.map(\.text), ["文字大意", "画面大意"])
        XCTAssertEqual(result.blocks?.filter { $0.kind == .listItem }.count, 4)
        let html = String(decoding: TranslationDocument.html(result, settings: settings), as: UTF8.self)
        XCTAssertTrue(html.contains("<summary>查看原文</summary>")); XCTAssertTrue(html.contains("<h1>画面大意</h1>"))
        XCTAssertTrue(html.contains("不加酱汁")); XCTAssertFalse(html.contains("未生成本地 OCR"))
    }

    @MainActor func testJapaneseReaderRendersColumnsListsAndFullEndingWithoutOverflow() async throws {
        var result = TranslationResult(original: "ランチメニュー", translated: "", sourceLanguages: "日语", target: "中文", engine: "fixture", elapsed: 0)
        result.mode = .professional
        result.blocks = [.init(id: 1, text: "午餐菜单", kind: .heading),
            .init(id: 2, text: "如需去除其中任一种配料，将不加酱汁。", kind: .paragraph),
            .init(id: 3, text: "套餐 1,100日元（含税）", kind: .field),
            .init(id: 4, text: "咖啡 450日元", kind: .field),
            .init(id: 5, text: "数量：1", kind: .field),
            .init(id: 6, text: "1. 咖啡", kind: .listItem), .init(id: 7, text: "2. 红茶", kind: .listItem),
            .init(id: 8, text: "仅限会员；优惠截至2026/10/06，优惠券不可叠加。", kind: .paragraph),
            .init(id: 9, text: "加入购物车 <script>不可执行</script>", kind: .paragraph)]
        result.translated = result.blocks!.map(\.text).joined(separator: "\n\n")
        let html = String(decoding: TranslationDocument.html(result), as: UTF8.self)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 780))
        let loaded = expectation(description: "Reader loaded")
        let delegate = ReaderNavigationObserver { loaded.fulfill() }
        view.navigationDelegate = delegate
        view.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 10)
        let stats = try await view.evaluateJavaScript("""
        (() => ({width: document.documentElement.scrollWidth, viewport: window.innerWidth,
          headings: [...document.querySelectorAll('h1')].map(e => e.textContent),
          fields: [...document.querySelectorAll('.field-row')].map(e => [e.firstChild.textContent, e.lastChild.textContent]),
          numbers: [...document.querySelectorAll('li.numbered')].map(e => getComputedStyle(e).listStyleType),
          scripts: document.querySelectorAll('script').length,
          ending: document.querySelector('main').lastElementChild.textContent,
          paragraphFont: getComputedStyle(document.querySelector('main > p')).fontSize,
          headingFont: getComputedStyle(document.querySelector('h1')).fontSize}))()
        """) as! [String: Any]
        XCTAssertLessThanOrEqual(stats["width"] as! Double, stats["viewport"] as! Double)
        XCTAssertEqual(stats["headings"] as? [String], ["午餐菜单"])
        XCTAssertEqual(stats["fields"] as? [[String]], [["套餐", "1,100日元（含税）"], ["咖啡", "450日元"], ["数量", "1"]])
        XCTAssertEqual(stats["numbers"] as? [String], ["none", "none"])
        XCTAssertEqual(stats["scripts"] as? Int, 0)
        XCTAssertEqual(stats["ending"] as? String, "加入购物车 <script>不可执行</script>")
        XCTAssertEqual(stats["paragraphFont"] as? String, "17px"); XCTAssertEqual(stats["headingFont"] as? String, "20px")
        let screenshot = try await view.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: screenshot); attachment.name = "日语菜单译文WebKit排版-1.9"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

@MainActor private final class ReaderNavigationObserver: NSObject, WKNavigationDelegate {
    var completed: () -> Void
    init(_ completed: @escaping () -> Void) { self.completed = completed }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { completed() }
}
