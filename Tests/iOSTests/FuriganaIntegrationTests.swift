import XCTest
import CoreText
import UIKit
import WebKit
@testable import ScreenTranslate

@MainActor
final class FuriganaIntegrationTests: XCTestCase {
    func testStandaloneReaderCanToggleRubyAndKeepsItAboveBaseText() async throws {
        let value = TranslationResult(original: "A Japanese sentence", translated: "日本語の文章を読みます。", sourceLanguages: "英语", target: "日语", engine: "fixture", elapsed: 0.1)
        var settings = AppSettings(); settings.reader.showJapaneseFurigana = true
        let html = String(decoding: TranslationDocument.html(value, settings: settings), as: UTF8.self)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let loaded = expectation(description: "Full reader loaded")
        let observer = ReaderNavigationObserver { loaded.fulfill() }
        web.navigationDelegate = observer
        web.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        let metrics = try await web.evaluateJavaScript("""
        (() => {
          const ruby = document.querySelector('ruby'), rt = ruby.querySelector('rt');
          const range = document.createRange(); range.selectNodeContents(ruby.firstChild);
          const base = range.getBoundingClientRect(), top = rt.getBoundingClientRect();
          return { baseTop:base.top, rubyBottom:top.bottom, baseSize:parseFloat(getComputedStyle(ruby).fontSize),
                   rubySize:parseFloat(getComputedStyle(rt).fontSize), display:getComputedStyle(rt).display };
        })()
        """) as! [String: Any]
        XCTAssertNotEqual(metrics["display"] as? String, "none")
        XCTAssertGreaterThan(metrics["rubyBottom"] as! Double, 0)
        XCTAssertLessThanOrEqual(metrics["rubyBottom"] as! Double, (metrics["baseTop"] as! Double) + 2)
        XCTAssertEqual(metrics["rubySize"] as! Double, (metrics["baseSize"] as! Double) * 0.5, accuracy: 0.1)
        let hidden = try await web.evaluateJavaScript("document.querySelector('#show-furigana').click(); getComputedStyle(document.querySelector('rt')).display")
        XCTAssertEqual(hidden as? String, "none")
        let shown = try await web.evaluateJavaScript("document.querySelector('#show-furigana').click(); getComputedStyle(document.querySelector('rt')).display")
        XCTAssertNotEqual(shown as? String, "none")
    }

    func testRubyIsCenteredAboveKanjiAtHalfSizeAndBaseStringIsUnchanged() throws {
        let text = "日本語の文章を読む。"
        let attributed = RubyTextLayout.attributed(text, annotations: JapaneseFurigana.annotations(for: text), reader: .init())
        XCTAssertEqual(attributed.string, text)
        let ruby = try XCTUnwrap(attributed.attribute(NSAttributedString.Key(kCTRubyAnnotationAttributeName as String), at: 0, effectiveRange: nil)) as! CTRubyAnnotation
        XCTAssertEqual(CTRubyAnnotationGetAlignment(ruby), .center)
        XCTAssertEqual(CTRubyAnnotationGetSizeFactor(ruby), 0.5)
        XCTAssertEqual(CTRubyAnnotationGetTextForPosition(ruby, .before) as String?, "にほんご")
        XCTAssertNil(CTRubyAnnotationGetTextForPosition(ruby, .after))
        XCTAssertNil(attributed.attribute(NSAttributedString.Key(kCTRubyAnnotationAttributeName as String), at: 3, effectiveRange: nil), "の remains unannotated")
    }

    func testNarrowColumnsAndLargeFontsKeepEveryCharacterVisible() {
        let text = "今日、学校で日本語の文章を読みます。取り扱い方法を確認してください。\n\n次の段落にも翻訳があります。"
        for width in [100.0, 180.0, 340.0] {
            for size in [12.0, 30.0] {
                for spacing in [0.0, 20.0] {
                    let view = RubyTextCanvas()
                    view.setContent(RubyTextLayout.attributed(text, annotations: JapaneseFurigana.annotations(for: text),
                        reader: .init(font: .serif, customFontSize: size, customLineSpacing: spacing), scale: 1.5))
                    let measured = view.measuredSize(width: width)
                    XCTAssertTrue(measured.height.isFinite)
                    let frame = view.textFrame(size: measured)
                    XCTAssertEqual(CTFrameGetVisibleStringRange(frame).length, (text as NSString).length,
                        "Clipped ruby layout: width \(width), font \(size), spacing \(spacing)")
                    let lines = CTFrameGetLines(frame) as! [CTLine]
                    var origins = [CGPoint](repeating: .zero, count: lines.count)
                    CTFrameGetLineOrigins(frame, CFRange(), &origins)
                    for index in 1..<lines.count { XCTAssertLessThan(origins[index].y, origins[index - 1].y) }
                }
            }
        }
    }

    func testFullReaderRubyToggleEscapesContentAndDoesNotAnnotateOriginalOrChinese() {
        var settings = AppSettings(); settings.reader.showJapaneseFurigana = true
        var value = TranslationResult(original: "日本語 <script>source</script>", translated: "日本語 <script>translation</script>",
            sourceLanguages: "中文", target: "日语", engine: "fixture", elapsed: 0.1)
        value.blocks = [.init(id: 1, text: value.translated, kind: .paragraph),
            .init(id: 2, text: "• 食べ物", kind: .listItem), .init(id: 3, text: "料金\t時間", kind: .tableHeader),
            .init(id: 4, text: "無料\t午前", kind: .tableRow)]
        let html = String(decoding: TranslationDocument.html(value, settings: settings), as: UTF8.self)
        XCTAssertTrue(html.contains("id=\"show-furigana\" checked"))
        XCTAssertTrue(html.contains("<ruby>日本語<rt aria-hidden=\"true\">にほんご</rt></ruby>"))
        XCTAssertTrue(html.contains("<li><ruby>食<rt")); XCTAssertTrue(html.contains("<td><ruby>無料<rt"))
        XCTAssertTrue(html.contains("日本語 &lt;script&gt;source&lt;/script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
        settings.reader.showJapaneseFurigana = false
        let hidden = String(decoding: TranslationDocument.html(value, settings: settings), as: UTF8.self)
        XCTAssertTrue(hidden.contains("id=\"show-furigana\"><label")); XCTAssertFalse(hidden.contains("id=\"show-furigana\" checked"))
        value.target = "中文"
        let chinese = String(decoding: TranslationDocument.html(value, settings: settings), as: UTF8.self)
        XCTAssertFalse(chinese.contains("<ruby>")); XCTAssertFalse(chinese.contains("<input"))
    }
}

@MainActor
private final class ReaderNavigationObserver: NSObject, WKNavigationDelegate {
    let loaded: () -> Void
    init(loaded: @escaping () -> Void) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded() }
}
