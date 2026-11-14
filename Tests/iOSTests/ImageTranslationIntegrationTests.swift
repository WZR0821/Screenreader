import XCTest
import WebKit
import ImageIO
import UniformTypeIdentifiers
@testable import ScreenTranslate

/// Answers a stubbed request in the format it used: numbered blocks
/// (professional mode, 原图直译) or plain text (quick mode without 原图直译).
func imageLayoutResponse(_ request: URLRequest, transform: (String) -> String) throws -> (Int, Data) {
    let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
    let text = (body["messages"] as! [[String: Any]]).last!["content"] as! String
    let content: String
    if let document = try? JSONDecoder().decode(ProfessionalLayout.Document.self, from: Data(text.utf8)) {
        let output = ProfessionalLayout.Document(blocks: document.blocks.reversed().map { .init(id: $0.id, text: transform($0.text)) })
        content = String(decoding: try JSONEncoder().encode(output), as: UTF8.self)
    } else { content = transform(text) }
    return (200, try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content], "finish_reason": "stop"]]]))
}

@MainActor final class ImageTranslationIntegrationTests: XCTestCase {
    private func fixture() -> (Data, TranslationResult) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1200), format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 720, height: 1200))
            ("Breakfast menu" as NSString).draw(at: CGPoint(x: 50, y: 70), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 40), .foregroundColor: UIColor.black])
            ("Coffee 450 yen" as NSString).draw(at: CGPoint(x: 50, y: 220), withAttributes: [.font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.black])
        }
        let blocks: [ReadingBlock] = [
            .init(id: 1, text: "早餐菜单", kind: .heading, original: "Breakfast menu", sourceBox: .init(x: 0.07, y: 0.89, width: 0.7, height: 0.05)),
            .init(id: 2, text: "咖啡450日元 <script>test</script>", original: "Coffee 450 yen", sourceBox: .init(x: 0.07, y: 0.77, width: 0.7, height: 0.04))]
        return (data, .init(original: "Breakfast menu\n\nCoffee 450 yen", translated: blocks.map(\.text).joined(separator: "\n\n"),
            sourceLanguages: "英语", target: "中文", engine: "fixture", elapsed: 0.1, mode: .quick, blocks: blocks))
    }

    func testQuickImagePipelineKeepsBlockIDsBoundsAndCacheWithoutUploadingPixels() async throws {
        let (data, _) = fixture()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        let count = RequestCounter()
        StubURLProtocol.registry.set { request in
            count.increment(); XCTAssertFalse(String(decoding: requestBody(request), as: UTF8.self).contains("image_url"))
            return try imageLayoutResponse(request) { $0.replacingOccurrences(of: "Breakfast menu", with: "早餐菜单").replacingOccurrences(of: "Coffee", with: "咖啡").replacingOccurrences(of: "yen", with: "日元") }
        }
        var settings = AppSettings(); settings.provider = .custom; settings.source = .english; settings.imageOverlay = true
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "fixture"
        let pipeline = TranslationPipeline(client: APIClient(session: session))
        let first = try await pipeline.image(data, settings: settings, key: "fixture-key")
        let second = try await pipeline.image(data, settings: settings, key: "fixture-key")
        XCTAssertEqual(first.mode, .quick); XCTAssertFalse(ImageTranslationLayout.items(in: first).isEmpty)
        XCTAssertEqual(first.blocks, second.blocks); XCTAssertEqual(count.value, 1)
        XCTAssertEqual(second.usedCache, true); XCTAssertTrue(first.translated.contains("450"))
        XCTAssertTrue(first.blocks!.allSatisfy { $0.original != nil && $0.sourceBox?.isValid == true })
    }

    func testOrientedPresentationMatchesVisionAndDropsMetadata() throws {
        let original = UIImage(data: fixture().0)!.cgImage!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, original, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let prepared = try XCTUnwrap(SourceImagePresentation.prepare(data as Data))
        XCTAssertEqual(prepared.width, 1200); XCTAssertEqual(prepared.height, 720)
        let source = CGImageSourceCreateWithData(prepared.data as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertTrue(properties[kCGImagePropertyOrientation] == nil || (properties[kCGImagePropertyOrientation] as? Int) == 1)
        XCTAssertNil(SourceImagePresentation.prepare(Data("not an image".utf8)))
    }

    func testCanvasUsesBottomLeftBoxesAndOriginalToggleRemovesAllInteractiveTiles() throws {
        let (data, result) = fixture()
        let canvas = ImageTranslationCanvasView(frame: CGRect(x: 0, y: 0, width: 360, height: 600))
        let image = try XCTUnwrap(UIImage(data: data)), items = ImageTranslationLayout.items(in: result)
        var selected: Int?
        canvas.configure(image: image, items: items, original: false, reader: .init(), target: "中文", enabled: true) { selected = $0 }
        canvas.layoutIfNeeded()
        let tiles = canvas.subviews.compactMap { $0 as? ImageTranslationTile }
        // The source text is 25.2, 36, 252 × 30; the margin is 12% of that line.
        XCTAssertEqual(tiles.count, 2); XCTAssertEqual(tiles[0].frame.minX, 21.6, accuracy: 0.01)
        XCTAssertEqual(tiles[0].frame.minY, 32.4, accuracy: 0.01)
        XCTAssertTrue(tiles[0].frame.contains(CGRect(x: 25.2, y: 36, width: 252, height: 30)))
        XCTAssertEqual(tiles[0].placement, ImageTranslationLayout.placement(of: items[0], in: canvas.bounds.size).local)
        XCTAssertNil(tiles[0].palette, "Without the pixels the tile keeps the system colours")
        let light = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertEqual(tiles[0].backgroundColor?.resolvedColor(with: light), UIColor.systemBackground.resolvedColor(with: light))
        tiles[0].sendActions(for: .touchUpInside); XCTAssertEqual(selected, 1)
        canvas.configure(image: image, items: items, original: true, reader: .init(), target: "中文", enabled: true) { selected = $0 }
        XCTAssertTrue(tiles.allSatisfy(\.isHidden)); XCTAssertEqual(canvas.accessibilityLabel, "原始图片")
    }

    func testTypographyFitsRubyAndVerticalTextAndReportsOverflow() {
        var item = ImageTranslationLayout.items(in: fixture().1)[0]
        func placed(_ size: CGSize) -> ImageTranslationLayout.Placement {
            let rect = CGRect(origin: .zero, size: size)
            return .init(tile: rect, text: rect, line: item.vertical ? size.width : size.height, pitch: nil, rows: 1,
                         single: true, alignment: .leading, padding: 0)
        }
        item.text = "日本語"; item.heading = false
        let ruby = ImageOverlayTypography.fitted(item: item, placement: placed(CGSize(width: 160, height: 44)), color: .black,
            annotations: JapaneseFurigana.annotations(for: item.text))
        XCTAssertFalse(ruby.truncated); XCTAssertGreaterThanOrEqual(ruby.fontSize, 8)
        XCTAssertNil(ruby.lineHeight, "Furigana keeps CoreText's own line spacing")
        item.vertical = true; item.text = "縦書きの文章"
        XCTAssertFalse(ImageOverlayTypography.fitted(item: item, placement: placed(CGSize(width: 32, height: 180)), color: .black).truncated)
        item.vertical = false; item.text = String(repeating: "完整译文", count: 80)
        XCTAssertTrue(ImageOverlayTypography.fitted(item: item, placement: placed(CGSize(width: 30, height: 14)), color: .black).truncated)
    }

    func testQuickLookOverlaySwitchesToReadingAndOpensFullTextWithoutScripts() async throws {
        let (data, value) = fixture()
        let prepared = try XCTUnwrap(SourceImagePresentation.prepare(data))
        let html = String(decoding: TranslationDocument.html(value, image: prepared), as: UTF8.self)
        XCTAssertFalse(html.contains("<script>")); XCTAssertTrue(html.contains("&lt;script&gt;"))
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 700))
        let loaded = expectation(description: "Overlay document loaded")
        let observer = ImageDocumentNavigationObserver { loaded.fulfill() }
        web.navigationDelegate = observer; web.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        let metrics = try await web.evaluateJavaScript("""
        (()=>({width:document.documentElement.scrollWidth, viewport:innerWidth,
          image:document.querySelector('.image-canvas img').naturalWidth,
          count:document.querySelectorAll('.overlay-word').length,
          main:getComputedStyle(document.querySelector('main')).display,
          position:document.querySelector('.overlay-word').getBoundingClientRect().top-document.querySelector('.image-canvas').getBoundingClientRect().top,
          canvasWidth:document.querySelector('.image-canvas').getBoundingClientRect().width}))()
        """) as! [String: Any]
        XCTAssertLessThanOrEqual(metrics["width"] as! Double, metrics["viewport"] as! Double)
        XCTAssertEqual(metrics["image"] as? Int, prepared.width); XCTAssertEqual(metrics["count"] as? Int, 2)
        // The same tile as the app's, on the 360-point reference canvas.
        let tile = ImageTranslationLayout.placement(of: ImageTranslationLayout.items(in: value)[0],
                                                    in: CGSize(width: 360, height: 360 * Double(prepared.height) / Double(prepared.width))).tile
        XCTAssertEqual(metrics["main"] as? String, "none")
        XCTAssertEqual(metrics["position"] as! Double, (metrics["canvasWidth"] as! Double) * tile.minY / 360, accuracy: 0.1)
        let screenshot = try await web.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: screenshot); attachment.name = "1.3.0-快捷指令原图直译-320pt"; attachment.lifetime = .keepAlways; add(attachment)
        // Quick Look treats even same-document links as requests to leave Shortcuts.
        let inspection = try await web.evaluateJavaScript("""
        (() => {
          const initialURL = location.href;
          document.querySelector('.overlay-word').click();
          const detail = document.querySelector('.image-detail');
          const opened = getComputedStyle(detail).display === 'flex';
          detail.querySelector('header label').click();
          return opened && getComputedStyle(detail).display === 'none' && location.href === initialURL;
        })()
        """)
        XCTAssertEqual(inspection as? Bool, true)
        _ = try await web.evaluateJavaScript("document.querySelector('#image-original').click(); true")
        let hidden = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.image-overlay')).display")
        XCTAssertEqual(hidden as? String, "none")
        let reading = try await web.evaluateJavaScript("document.querySelector('#presentation-reading').click(); getComputedStyle(document.querySelector('main')).display")
        XCTAssertNotEqual(reading as? String, "none")
    }

    func testQuickLookImageRubyToggleKeepsReadingAboveKanjiWithinTheRegion() async throws {
        let (data, original) = fixture()
        var value = original; value.target = "日语"
        value.blocks = [ReadingBlock(id: 1, text: "日本語", original: "Japanese",
            sourceBox: .init(x: 0.07, y: 0.84, width: 0.7, height: 0.1))]
        value.translated = "日本語"
        let prepared = try XCTUnwrap(SourceImagePresentation.prepare(data))
        let html = String(decoding: TranslationDocument.html(value, image: prepared), as: UTF8.self)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 700))
        let loaded = expectation(description: "Japanese image reader loaded")
        let observer = ImageDocumentNavigationObserver { loaded.fulfill() }
        web.navigationDelegate = observer; web.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        let hidden = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.overlay-word rt')).display")
        XCTAssertEqual(hidden as? String, "none")
        let metrics = try await web.evaluateJavaScript("""
        document.querySelector('#show-furigana').click();
        (()=>{const tile=document.querySelector('.overlay-word'), rt=tile.querySelector('rt');
          return {ruby:getComputedStyle(rt).display, size:parseFloat(getComputedStyle(rt).fontSize),
            base:parseFloat(getComputedStyle(tile.querySelector('.overlay-text')).fontSize), top:rt.getBoundingClientRect().top,
            tileTop:tile.getBoundingClientRect().top, bottom:rt.getBoundingClientRect().bottom,
            tileBottom:tile.getBoundingClientRect().bottom};})()
        """) as! [String: Any]
        XCTAssertNotEqual(metrics["ruby"] as? String, "none")
        XCTAssertLessThan(metrics["size"] as! Double, metrics["base"] as! Double)
        XCTAssertGreaterThanOrEqual(metrics["top"] as! Double, (metrics["tileTop"] as! Double) - 1)
        XCTAssertLessThanOrEqual(metrics["bottom"] as! Double, metrics["tileBottom"] as! Double)
    }
}

@MainActor private final class ImageDocumentNavigationObserver: NSObject, WKNavigationDelegate {
    let loaded: () -> Void
    init(loaded: @escaping () -> Void) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded() }
}
