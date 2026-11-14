import XCTest
import UIKit
import WebKit
import CoreText
@testable import ScreenTranslate

/// 1.3.3: a translated label sits where the source text was, on the source
/// line positions, never larger than the source text and in the screenshot's
/// own colours, in the app and in the shortcut's Quick Look page alike.
@MainActor final class Release133OverlayTests: XCTestCase {
    private static let navy = ThemeRGB(red: 30 / 255, green: 58 / 255, blue: 138 / 255)

    /// A 720 × 1200 screenshot shown on a 360 × 600 canvas: white text on navy,
    /// a centred title over a paragraph of three lines 40 points apart.
    private static func fixture() -> (Data, TranslationResult) {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1200), format: format).pngData { context in
            UIColor(rgb: navy).setFill(); context.fill(CGRect(x: 0, y: 0, width: 720, height: 1200))
            let white: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.white]
            ("Breakfast" as NSString).draw(at: CGPoint(x: 270, y: 96), withAttributes: white)
            for (index, line) in ["Freshly baked bread", "and coffee are served", "every morning."].enumerated() {
                (line as NSString).draw(at: CGPoint(x: 60, y: 300 + index * 80), withAttributes: white)
            }
        }
        // Canvas points: the title is 108, 48, 144 × 24; the paragraph 30, 150, 300 × 100.
        var title = ReadingBlock(id: 1, text: "早餐", kind: .heading, original: "Breakfast",
                                 sourceBox: .init(x: 0.3, y: 0.88, width: 0.4, height: 0.04))
        title.sourceLineHeight = 0.04; title.sourceLineCount = 1
        var paragraph = ReadingBlock(id: 2, text: "现烤面包\n和咖啡\n每天早上供应。",
                                     original: "Freshly baked bread\nand coffee are served\nevery morning.",
                                     sourceBox: .init(x: 30.0 / 360, y: 1 - 250.0 / 600, width: 300.0 / 360, height: 100.0 / 600))
        paragraph.sourceLineHeight = 20.0 / 600; paragraph.sourceLineCount = 3
        let blocks = [title, paragraph]
        return (data, .init(original: blocks.compactMap(\.original).joined(separator: "\n\n"),
                            translated: blocks.map(\.text).joined(separator: "\n\n"), sourceLanguages: "英语", target: "中文",
                            engine: "fixture", elapsed: 0.1, mode: .quick, blocks: blocks))
    }

    /// Each line's glyph bounds in the tile's own top-left coordinates.
    private static func ink(_ fit: ImageOverlayTypography.Fitted) -> [CGRect] {
        let lines = CTFrameGetLines(fit.frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(fit.frame, CFRange(location: 0, length: 0), &origins)
        return zip(lines, origins).map { line, origin in
            let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            // CoreText measures upwards from the bottom of the frame's path.
            return CGRect(x: fit.rect.minX + origin.x + glyphs.minX, y: fit.rect.maxY - origin.y - glyphs.maxY,
                          width: glyphs.width, height: glyphs.height)
        }
    }

    private static func assertClose(_ value: ThemeRGB, _ expected: ThemeRGB, within tolerance: Double,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value.red, expected.red, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(value.green, expected.green, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(value.blue, expected.blue, accuracy: tolerance, file: file, line: line)
    }

    /// How much of a rendered label is the screenshot's navy, and how much light text.
    private static func shares(_ tile: UIView) -> (navy: Double, light: Double) {
        tile.setNeedsDisplay(); tile.layer.displayIfNeeded()
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: tile.bounds, format: format).image { tile.layer.render(in: $0.cgContext) }
        guard let picture = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return (0, 0) }
        let width = picture.width, height = picture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?
                .draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var navy = 0, light = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let red = Int(bytes[offset]), green = Int(bytes[offset + 1]), blue = Int(bytes[offset + 2])
            if abs(red - 30) + abs(green - 58) + abs(blue - 138) < 30 { navy += 1 }
            if min(red, green, blue) > 215 { light += 1 }
        }
        let total = Double(max(1, width * height))
        return (Double(navy) / total, Double(light) / total)
    }

    func testParagraphLinesSitOnTheSourceLinesAtTheSourceSize() {
        let item = ImageTranslationLayout.items(in: Self.fixture().1)[1]
        let placement = ImageTranslationLayout.placement(of: item, in: CGSize(width: 360, height: 600))
        XCTAssertEqual(placement.rows, 3); XCTAssertEqual(placement.pitch ?? 0, 40, accuracy: 0.01)
        XCTAssertEqual(placement.alignment, .leading)
        let local = placement.local
        let fit = ImageOverlayTypography.fitted(item: item, placement: local, color: .white)
        XCTAssertFalse(fit.truncated)
        XCTAssertEqual(fit.fontSize, 17, accuracy: 0.01, "No larger than 85% of the 20-point source line")
        XCTAssertEqual(fit.lineHeight ?? 0, 40, accuracy: 0.01)
        let lines = Self.ink(fit)
        XCTAssertEqual(lines.count, 3)
        for (row, glyphs) in lines.enumerated() {
            XCTAssertEqual(glyphs.midY, local.text.minY + CGFloat(row) * 40 + 10, accuracy: 1.6, "line \(row + 1)")
        }
        XCTAssertEqual(lines.map(\.minX).min() ?? 0, local.text.minX, accuracy: 2)
    }

    func testShortTitleStaysCentredAndALongerOneShrinksOnItsOwnLine() {
        var item = ImageTranslationLayout.items(in: Self.fixture().1)[0]
        let placement = ImageTranslationLayout.placement(of: item, in: CGSize(width: 360, height: 600))
        XCTAssertTrue(placement.single); XCTAssertEqual(placement.alignment, .center)
        let local = placement.local
        let short = ImageOverlayTypography.fitted(item: item, placement: local, color: .white)
        let glyphs = Self.ink(short)
        XCTAssertEqual(glyphs.count, 1); XCTAssertEqual(short.fontSize, 20.4, accuracy: 0.01)
        XCTAssertEqual(glyphs.first?.midX ?? 0, local.text.midX, accuracy: 1.5)
        XCTAssertEqual(glyphs.first?.midY ?? 0, local.text.midY, accuracy: 1.9)

        // Too long for the source size: smaller type, still centred on the line.
        item.text = "全天供应早餐和咖啡饮品"
        let long = ImageOverlayTypography.fitted(item: item, placement: local, color: .white)
        let shrunk = Self.ink(long)
        XCTAssertFalse(long.truncated); XCTAssertEqual(shrunk.count, 1)
        XCTAssertLessThan(long.fontSize, 20.4 * 0.7)
        XCTAssertEqual(shrunk.first?.midY ?? 0, local.text.midY, accuracy: 1.9)
        XCTAssertEqual(shrunk.first?.midX ?? 0, local.text.midX, accuracy: 1.9)
    }

    func testTilesTakeTheirColoursFromTheScreenshot() throws {
        let (data, result) = Self.fixture()
        let prepared = try XCTUnwrap(SourceImagePresentation.prepare(data))
        let image = try XCTUnwrap(UIImage(data: prepared.data))
        let pixels = try XCTUnwrap(ImageOverlayPalette.Pixels(data: prepared.data))
        let canvas = ImageTranslationCanvasView(frame: CGRect(x: 0, y: 0, width: 360, height: 600))
        let items = ImageTranslationLayout.items(in: result)
        canvas.configure(image: image, pixels: pixels, items: items, original: false, reader: .init(), target: "中文", enabled: true) { _ in }
        canvas.layoutIfNeeded()
        let tiles = canvas.subviews.compactMap { $0 as? ImageTranslationTile }
        XCTAssertEqual(tiles.count, 2)
        for tile in tiles {
            let palette = try XCTUnwrap(tile.palette, tile.item.id)
            Self.assertClose(palette.background, Self.navy, within: 0.03)
            Self.assertClose(palette.ink, .hex(0xffffff), within: 0.08)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            let resolved = tile.backgroundColor?.getRed(&red, green: &green, blue: &blue, alpha: &alpha) ?? false
            XCTAssertTrue(resolved)
            Self.assertClose(ThemeRGB(red: red, green: green, blue: blue), palette.background, within: 0.002)
            let shares = Self.shares(tile)
            XCTAssertGreaterThan(shares.navy, 0.6, "\(tile.item.id) keeps the screenshot's background")
            XCTAssertGreaterThan(shares.light, 0.01, "\(tile.item.id) draws the translation in the screenshot's text colour")
        }
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: canvas.bounds).image { canvas.layer.render(in: $0.cgContext) })
        attachment.name = "1.3.3-原图直译取色与行位"; attachment.lifetime = .keepAlways; add(attachment)

        // Until the screenshot has been read, labels use the system colours.
        canvas.configure(image: image, pixels: nil, items: items, original: false, reader: .init(), target: "中文", enabled: true) { _ in }
        XCTAssertTrue(tiles.allSatisfy { $0.palette == nil })
    }

    func testQuickLookPageUsesTheSameColoursAndLinePositions() async throws {
        let (data, value) = Self.fixture()
        let prepared = try XCTUnwrap(SourceImagePresentation.prepare(data))
        let html = String(decoding: TranslationDocument.html(value, image: prepared), as: UTF8.self)
        let pattern = try NSRegularExpression(pattern: #"background:rgb\((\d+),(\d+),(\d+)\);color:rgb\((\d+),(\d+),(\d+)\)"#)
        let matches = pattern.matches(in: html, range: NSRange(html.startIndex..., in: html))
        XCTAssertEqual(matches.count, 2)
        for match in matches {
            let rgb = (1...6).map { Int((html as NSString).substring(with: match.range(at: $0))) ?? -1 }
            XCTAssertLessThanOrEqual(abs(rgb[0] - 30) + abs(rgb[1] - 58) + abs(rgb[2] - 138), 12)
            XCTAssertGreaterThanOrEqual(rgb[3...5].min() ?? 0, 225)
        }
        let canvasSize = CGSize(width: 360, height: 360 * Double(prepared.height) / Double(prepared.width))
        let paragraph = ImageTranslationLayout.placement(of: ImageTranslationLayout.items(in: value)[1], in: canvasSize)
        let pitch = try XCTUnwrap(paragraph.pitch)
        func cqw(_ points: CGFloat) -> String {
            String(format: "%.3fcqw", locale: Locale(identifier: "en_US_POSIX"), Double(points) / 360 * 100)
        }
        XCTAssertTrue(html.contains("font-size:\(cqw(17));line-height:\(cqw(pitch))"))
        XCTAssertTrue(html.contains("text-align:center"))

        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 900))
        let loaded = expectation(description: "Quick Look page loaded")
        let observer = OverlayPageObserver { loaded.fulfill() }
        web.navigationDelegate = observer; web.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        // Only the glyph runs: the boxes around each line would sit exactly on
        // the grid whatever WebKit does with the text inside them.
        let metrics = try await web.evaluateJavaScript("""
        (()=>{const canvas=document.querySelector('.image-canvas').getBoundingClientRect();
          const block=document.querySelectorAll('.overlay-text')[1], range=document.createRange(), lines=[];
          const walker=document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
          while (walker.nextNode()) { range.selectNodeContents(walker.currentNode);
            for (const r of range.getClientRects()) if (r.width>1&&r.height>1) lines.push((r.top+r.bottom)/2); }
          return {width:canvas.width, top:canvas.top, lines:lines,
            texts:[...block.querySelectorAll('.overlay-line')].map(e=>e.textContent)};})()
        """) as! [String: Any]
        // The page keeps the app's line breaks instead of wrapping on its own.
        XCTAssertEqual(metrics["texts"] as? [String], ["现烤面包", "和咖啡", "每天早上供应。"])
        let scale = (metrics["width"] as! Double) / 360, top = metrics["top"] as! Double
        var lines: [Double] = []
        for centre in (metrics["lines"] as! [Double]).map({ ($0 - top) / scale }).sorted()
        where lines.last.map({ centre - $0 > 2 }) ?? true { lines.append(centre) }
        XCTAssertEqual(lines.count, 3)
        for (row, centre) in lines.enumerated() {
            XCTAssertEqual(centre, Double(paragraph.text.minY + CGFloat(row) * pitch + paragraph.line / 2),
                           accuracy: Double(paragraph.line) * 0.1, "line \(row + 1)")
        }
        // WebKit's whole-pixel line-height used to take about 0.9 pt off every
        // step on this page; each step now has to match the source pitch.
        for (upper, lower) in zip(lines, lines.dropFirst()) {
            XCTAssertEqual(lower - upper, Double(pitch), accuracy: 0.5)
        }
        let screenshot = try await web.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: screenshot); attachment.name = "1.3.3-快捷指令原图直译-取色与行位"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    /// A translation too long for its tile ends in a "…" at the text's own
    /// size. Once the size moved onto the inner text, the mark fell back to
    /// the page's reading size and stood out above small labels.
    func testQuickLookOverflowMarkKeepsTheTextSize() async throws {
        let (data, _) = Self.fixture()
        // 120 characters; at the smallest size, 8 points, fewer than 60 fit here.
        var title = ReadingBlock(id: 1, text: String(repeating: "早餐菜单每天早上七点开始供应。", count: 8), kind: .heading,
                                 original: "Breakfast", sourceBox: .init(x: 0.3, y: 0.88, width: 0.4, height: 0.04))
        title.sourceLineHeight = 0.04; title.sourceLineCount = 1
        let value = TranslationResult(original: "Breakfast", translated: title.text, sourceLanguages: "英语", target: "中文",
                                      engine: "fixture", elapsed: 0.1, mode: .quick, blocks: [title])
        let prepared = try XCTUnwrap(SourceImagePresentation.prepare(data))
        let html = String(decoding: TranslationDocument.html(value, image: prepared), as: UTF8.self)
        XCTAssertTrue(html.contains("overflow-mark"), "The fixture has to overflow its tile")

        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 900))
        let loaded = expectation(description: "Quick Look page loaded")
        let observer = OverlayPageObserver { loaded.fulfill() }
        web.navigationDelegate = observer; web.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        let sizes = try await web.evaluateJavaScript("""
        [...document.querySelectorAll('.overlay-text, .overflow-mark')].map(e => parseFloat(getComputedStyle(e).fontSize))
        """) as! [Double]
        XCTAssertEqual(sizes.count, 2)
        XCTAssertEqual(sizes.last ?? 0, sizes.first ?? -1, accuracy: 0.01, "The mark matches the translation, not the page")
    }
}

@MainActor private final class OverlayPageObserver: NSObject, WKNavigationDelegate {
    let loaded: () -> Void
    init(loaded: @escaping () -> Void) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded() }
}
