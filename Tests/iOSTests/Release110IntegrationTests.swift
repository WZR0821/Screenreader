import XCTest
import UIKit
import WebKit
import UniformTypeIdentifiers
@testable import ScreenTranslate

@MainActor
final class Release110IntegrationTests: XCTestCase {
    private func verticalImage() -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 820), format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 820))
            for (index, text) in ["日本語の縦書きです", "文字を確認します"].enumerated() {
                for (row, glyph) in text.enumerated() {
                    (String(glyph) as NSString).draw(at: CGPoint(x: 420 - index * 180, y: 70 + row * 60),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.black])
                }
            }
        }
    }

    func testUprightVerticalJapanesePixelsBecomeRightToLeftColumns() async throws {
        let data = verticalImage()
        let result = try await OCRService().recognize(data, source: .japanese, cleanScreenText: false, mode: .professional, direction: .vertical)
        let attachment = XCTAttachment(string: "OCR: \(result.text)\nVertical: \(result.lines.filter(\.vertical).map(\.text))\nRecognition \(result.recognitionSeconds), review \(result.refinementSeconds)")
        attachment.name = "1.1.0-vertical-ocr"; attachment.lifetime = .keepAlways; add(attachment)
        let image = XCTAttachment(image: UIImage(data: data)!); image.lifetime = .keepAlways; add(image)
        XCTAssertEqual(result.lines.filter(\.vertical).map(\.text), ["日本語の縦書きです", "文字を確認します"])
        XCTAssertEqual(result.text, "日本語の縦書きです\n\n文字を確認します")
        XCTAssertTrue(result.lowConfidence)
        XCTAssertEqual(result.reviewItems.filter { $0.reasons.contains("竖排阅读顺序与标点") }.count, 2)
    }

    func testHorizontalTextDoesNotTriggerVerticalReflow() async throws {
        let result = try await OCRService().recognize(DebugFixtures.image(), source: .japanese, cleanScreenText: false)
        XCTAssertFalse(result.lines.contains(where: \.vertical))
        XCTAssertFalse(result.text.isEmpty)
    }

    func testReviewAppliesOnlyConfirmedLineAndRetainsOtherWarnings() {
        let first = RecognizedLine(text: "価格 800円", x: 0.1, y: 0.6, width: 0.6, height: 0.04, confidence: 0.4)
        let second = RecognizedLine(text: "予約が必要", x: 0.1, y: 0.3, width: 0.6, height: 0.04, confidence: 0.4)
        let lines = [first, second]
        let items = OCRReview.items(lines, imageWidth: 1000, imageHeight: 1000, japanese: true)
        let original = OCRResult(text: OCRLayout.assemble(lines), languages: "日语", lowConfidence: true, lines: lines, reviewItems: items)
        let revised = original.reviewing([0: "価格 900円"])
        XCTAssertTrue(revised.text.contains("900円")); XCTAssertEqual(revised.reviewItems.map(\.id), [1])
        XCTAssertTrue(revised.lowConfidence)
        let unchanged = revised.reviewing([1: "   "])
        XCTAssertEqual(unchanged.reviewItems.count, 1)
        XCTAssertFalse(revised.reviewing([1: "予約が必要"]).lowConfidence)
    }

    func testClipboardLoadsTextAndImageAndRejectsTextInVisualMode() async throws {
        let string = NSItemProvider(object: "Copied text" as NSString)
        let text = try await ClipboardInput.load([string], imagesOnly: false)
        guard case .text(let value) = text else { return XCTFail("Expected text") }
        XCTAssertEqual(value, "Copied text")
        do { _ = try await ClipboardInput.load([string], imagesOnly: true); XCTFail("Visual mode requires an image") }
        catch { XCTAssertEqual(error as? TranslationError, .imageRequired) }
        let data = verticalImage()
        let picture = NSItemProvider()
        picture.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { callback in
            callback(data, nil); return nil
        }
        let image = try await ClipboardInput.load([picture, string], imagesOnly: false)
        guard case .image(let copied) = image else { return XCTFail("Expected image") }
        XCTAssertEqual(copied, data)
    }

    func testReplacingImageAndChangingSourceDiscardPreviousOCR() async throws {
        let suite = "Screenreader.110.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let model = TranslationViewModel(store: store)
        try model.acceptImage(DebugFixtures.image())
        model.recognize()
        // Real Vision can exceed ten seconds on an Intel simulator. Wait for
        // completion before checking state invalidation, with a bounded timeout.
        let deadline = Date().addingTimeInterval(45)
        while model.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(model.busy, "Vision did not finish within 45 seconds")
        XCTAssertNil(model.error)
        XCTAssertNotNil(model.recognizedOCR)
        model.resetRecognition()
        XCTAssertNil(model.recognizedOCR); XCTAssertEqual(model.text, "")
        model.text = "manually edited"
        try model.acceptImage(verticalImage())
        XCTAssertEqual(model.text, ""); XCTAssertNil(model.recognizedOCR)
        model.paste([NSItemProvider(object: "New text" as NSString)])
        for _ in 0..<100 where model.busy { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(model.text, "New text"); XCTAssertNil(model.imageData); XCTAssertNil(model.preview)
    }
    func testWideTableScrollsWithoutWideningTheDocumentOrLosingEmptyCells() async throws {
        var result = TranslationResult(original: "", translated: "", sourceLanguages: "日语", target: "中文", engine: "fixture", elapsed: 0)
        result.blocks = [.init(id: 1, text: "商品\t数量\t单价\t税率\t小计", kind: .tableHeader),
                         .init(id: 2, text: "茶\t2\t100日元\t\t200日元", kind: .tableRow),
                         .init(id: 3, text: "最后一行", kind: .paragraph)]
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let ready = expectation(description: "Wide table loaded")
        let observer = Release110ReaderObserver { ready.fulfill() }; view.navigationDelegate = observer
        view.loadHTMLString(String(decoding: TranslationDocument.html(result), as: UTF8.self), baseURL: nil)
        await fulfillment(of: [ready], timeout: 10)
        let sizes = try await view.evaluateJavaScript("""
        (() => ({page:document.documentElement.scrollWidth,viewport:innerWidth,
        scroll:document.querySelector('.table-scroll').scrollWidth,
        visible:document.querySelector('.table-scroll').clientWidth,
        cells:[...document.querySelectorAll('td')].map(x=>x.textContent),
        last:document.querySelector('main').lastChild.textContent}))()
        """) as! [String: Any]
        XCTAssertLessThanOrEqual(sizes["page"] as! Double, sizes["viewport"] as! Double + 1)
        XCTAssertGreaterThan(sizes["scroll"] as! Double, sizes["visible"] as! Double)
        XCTAssertEqual(sizes["cells"] as! [String], ["茶", "2", "100日元", "", "200日元"])
        XCTAssertEqual(sizes["last"] as? String, "最后一行")
        let attachment = XCTAttachment(image: try await view.takeSnapshot(configuration: nil))
        attachment.name = "1.1.0-wide-table-320"; attachment.lifetime = .keepAlways; add(attachment)
    }

}

private final class Release110ReaderObserver: NSObject, WKNavigationDelegate {
    let ready: () -> Void
    init(_ ready: @escaping () -> Void) { self.ready = ready }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready() }
}
