import XCTest
import CoreGraphics
import ImageIO
#if canImport(ScreenTranslateCore)
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

/// 1.3.3: 原图直译 is an optional module, quick mode asks the model for less
/// reasoning, and the connection opens while OCR runs. The overlay follows
/// the source lines and takes its colours from the screenshot.
final class Release133Tests: XCTestCase {
    private func body(_ provider: AIProvider, model: String, style: APIStyle? = nil,
                      reasoning: ReasoningEffort? = nil, mode: TranslationMode = .quick) -> [String: Any] {
        var settings = AppSettings()
        settings.provider = provider
        settings.mode = mode
        settings.configuration.model = model
        if let style { settings.configuration.style = style }
        settings.configuration.reasoning = reasoning
        var body: [String: Any] = ["model": model]
        if settings.configuration.style == .anthropicMessages { body["max_tokens"] = 8192 }
        APIClient.applyReasoning(to: &body, settings: settings, configuration: settings.configuration, model: model)
        return body
    }

    func testImageOverlayIsOffByDefaultAndSurvivesSaving() throws {
        XCTAssertFalse(AppSettings().imageOverlay)
        // Settings saved by 1.3.2 have no such key: they open with the module off.
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as! [String: Any]
        XCTAssertEqual(object["imageOverlay"] as? Bool, false)
        object.removeValue(forKey: "imageOverlay")
        let old = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(old.imageOverlay)
        var on = AppSettings(); on.imageOverlay = true
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on)).imageOverlay)
    }

    func testQuickModeAsksClaudeFiveForLowEffortOnly() {
        for model in ["claude-sonnet-5-5", "claude-opus-5-5", "claude-haiku-5-5", "claude-fable-5-2"] {
            let quick = body(.claude, model: model)
            XCTAssertEqual(quick["output_config"] as? [String: String], ["effort": "low"], model)
            XCTAssertNil(quick["thinking"], "Thinking stays adaptive: \(model)")
            XCTAssertEqual(body(.claude, model: model, mode: .professional).count, 2, "Professional mode sends no reasoning field: \(model)")
            XCTAssertEqual(body(.claude, model: model, mode: .visual).count, 2, model)
        }
        // Earlier models and endpoints that only look like Claude are left alone.
        XCTAssertEqual(body(.claude, model: "claude-haiku-4-5").count, 2)
        XCTAssertNil(body(.claude, model: "claude-sonnet-5-5", style: .chatCompletions)["output_config"])
        XCTAssertEqual(body(.custom, model: "claude-sonnet-5-5", style: .anthropicMessages).count, 2)
        // An explicit choice still wins over 自动.
        XCTAssertNotEqual(body(.claude, model: "claude-sonnet-5-5", reasoning: .high)["output_config"] as? [String: String], ["effort": "low"])
    }

    func testQuickModeUsesTheLowestGeminiFlashLevel() {
        func effort(_ model: String, mode: TranslationMode = .quick, provider: AIProvider = .gemini) -> String? {
            body(provider, model: model, style: .chatCompletions, mode: mode)["reasoning_effort"] as? String
        }
        XCTAssertEqual(effort("gemini-3.8-flash"), "minimal")
        XCTAssertEqual(effort("gemini-3.5-flash-lite"), "minimal")
        XCTAssertEqual(effort("gemini-4-flash"), "minimal")
        XCTAssertEqual(effort("gemini-2.5-flash"), "none")
        XCTAssertEqual(effort("gemini-2.5-flash-lite"), "none")
        // Pro models cannot lower thinking that far; professional mode keeps the default.
        XCTAssertNil(effort("gemini-3.8-pro"))
        XCTAssertNil(effort("gemini-2.5-pro"))
        XCTAssertNil(effort("gemini-3.8-flash", mode: .professional))
        XCTAssertNil(effort("gemini-3.8-flash", provider: .custom))
    }

    /// What 原图直译 costs in quick mode: the block protocol in the prompt, the
    /// JSON around every block, and the JSON the model must write back.
    func testPlainQuickRequestIsShorterThanNumberedBlocks() throws {
        let lines = ["Breakfast menu", "Freshly made every morning.", "Coffee 450 yen", "Tea 400 yen",
                     "Orange juice 500 yen", "Quantity 1", "Order before 11:30.", "Add to cart"]
        let replies = ["早餐菜单", "每天早上新鲜制作。", "咖啡 450 日元", "茶 400 日元", "橙汁 500 日元", "数量 1",
                       "请在 11:30 前下单。", "加入购物车"]
        let text = lines.joined(separator: "\n\n")
        let blocks = lines.enumerated().map { ReadingBlock(id: $0.offset + 1, text: $0.element, kind: .paragraph) }
        let layout = ProfessionalLayout(text, readingBlocks: blocks)
        let blockRequest = try layout.requestText().count + 1 + ProfessionalLayout.instructions.count
        let document = ProfessionalLayout.Document(blocks: replies.enumerated().map { .init(id: $0.offset + 1, text: $0.element) })
        let blockReply = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        XCTAssertEqual(try layout.restoreBlocks(blockReply).count, replies.count)
        let plainReply = replies.joined(separator: "\n\n")
        print("RELEASE133_PLAIN_VS_BLOCKS request \(text.count) vs \(blockRequest) characters, reply \(plainReply.count) vs \(blockReply.count)")
        XCTAssertLessThan(text.count, blockRequest)
        XCTAssertLessThan(plainReply.count, blockReply.count)
    }

    func testWarmUpRequestCarriesNoKeyOrContent() throws {
        var configuration = AppSettings().configuration
        configuration.baseURL = "https://api.example.test/v1"
        configuration.style = .chatCompletions
        let request = try XCTUnwrap(APIClient.warmUpRequest(configuration: configuration))
        XCTAssertEqual(request.httpMethod, "HEAD")
        XCTAssertEqual(request.url, try APIClient.endpoint(configuration: configuration))
        XCTAssertNil(request.httpBody)
        XCTAssertTrue(request.allHTTPHeaderFields?.isEmpty ?? true)
        configuration.baseURL = "http://api.example.test/v1"
        XCTAssertNil(APIClient.warmUpRequest(configuration: configuration), "Only HTTPS endpoints are contacted")
    }

    func testWarmUpNeverUsesASuppliedSession() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        let counter = RequestCounter()
        StubURLProtocol.registry.set { _ in counter.increment(); return (200, Data()) }
        var configuration = AppSettings().configuration
        configuration.baseURL = "https://api.example.test/v1"
        APIClient(session: session).warmUp(configuration: configuration)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(counter.value, 0)
    }

    // MARK: 原图直译 alignment

    func testBlocksRecordTheSourceLineAndHowManyLinesTheBoxHolds() throws {
        let lines = [RecognizedLine(text: "Every morning our bakers prepare fresh bread and", x: 0.08, y: 0.70, width: 0.84, height: 0.02, confidence: 1),
                     RecognizedLine(text: "pastries in the kitchen behind the counter, so the", x: 0.08, y: 0.67, width: 0.84, height: 0.02, confidence: 1),
                     RecognizedLine(text: "menu changes a little from day to day.", x: 0.08, y: 0.64, width: 0.6, height: 0.02, confidence: 1)]
        let blocks = OCRLayout.readingBlocks(lines)
        XCTAssertEqual(blocks.count, 1, blocks.map(\.text).description)
        let block = try XCTUnwrap(blocks.first)
        XCTAssertEqual(block.sourceLineCount, 3)
        XCTAssertEqual(try XCTUnwrap(block.sourceLineHeight), 0.02, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(block.sourceBox).height, 0.08, accuracy: 1e-9)

        // A stacked value is one OCR line holding two rows.
        let stacked = OCRLayout.readingBlocks([RecognizedLine(text: "Tokyo\nOsaka", x: 0.1, y: 0.4, width: 0.3, height: 0.06, confidence: 1)])
        XCTAssertEqual(stacked.first?.sourceLineCount, 2)
        XCTAssertEqual(try XCTUnwrap(stacked.first?.sourceLineHeight), 0.03, accuracy: 1e-9)
        // A price beside its item adds no row.
        let menu = OCRLayout.readingBlocks([RecognizedLine(text: "Coffee", x: 0.05, y: 0.5, width: 0.2, height: 0.03, confidence: 1),
                                            RecognizedLine(text: "450 yen", x: 0.75, y: 0.5, width: 0.2, height: 0.03, confidence: 1)])
        XCTAssertEqual(menu.count, 1); XCTAssertEqual(menu.first?.sourceLineCount, 1)
    }

    func testParagraphItemsKeepTheSourceLineSpacing() throws {
        let item = ImageTranslationLayout.Item(blockID: 1, cell: 0, text: "译文", original: "source",
            box: .init(x: 0.1, y: 0.5, width: 0.5, height: 0.1), vertical: false, heading: false, lineHeight: 0.02, rows: 3)
        let placement = ImageTranslationLayout.placement(of: item, in: CGSize(width: 400, height: 1000))
        func same(_ rect: CGRect, _ expected: CGRect, line: UInt = #line) {
            for (value, wanted) in zip([rect.minX, rect.minY, rect.width, rect.height],
                                       [expected.minX, expected.minY, expected.width, expected.height]) {
                XCTAssertEqual(value, wanted, accuracy: 1e-6, "\(rect) vs \(expected)", line: line)
            }
        }
        same(placement.text, CGRect(x: 40, y: 400, width: 200, height: 100))
        XCTAssertEqual(placement.line, 20, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(placement.pitch), 40, accuracy: 1e-9)
        XCTAssertEqual(placement.rows, 3); XCTAssertFalse(placement.single)
        // The margin grows with the type: about an eighth of a line, 1.5 to 5 points.
        XCTAssertEqual(placement.padding, 2.4, accuracy: 1e-9)
        same(placement.tile, CGRect(x: 37.6, y: 397.6, width: 204.8, height: 104.8))
        XCTAssertEqual(placement.local.tile.origin, .zero)
        XCTAssertEqual(placement.local.text.origin.x, 2.4, accuracy: 1e-9)

        var large = item; large.lineHeight = 0.08; large.rows = 1; large.box.height = 0.08
        XCTAssertEqual(ImageTranslationLayout.placement(of: large, in: CGSize(width: 400, height: 1000)).padding, 5)
        var small = item; small.lineHeight = 0.005; small.rows = 1; small.box.height = 0.005
        XCTAssertEqual(ImageTranslationLayout.placement(of: small, in: CGSize(width: 400, height: 1000)).padding, 1.5)
    }

    func testInconsistentOrUnknownLineCountsFallBackSafely() {
        let size = CGSize(width: 400, height: 1000)
        // Three "lines" in one line's height: pieces of one row, not three rows.
        var item = ImageTranslationLayout.Item(blockID: 1, cell: 0, text: "译文", original: "source",
            box: .init(x: 0.1, y: 0.5, width: 0.5, height: 0.02), vertical: false, heading: false, lineHeight: 0.02, rows: 3)
        var placement = ImageTranslationLayout.placement(of: item, in: size)
        XCTAssertEqual(placement.rows, 1); XCTAssertNil(placement.pitch); XCTAssertTrue(placement.single)
        // Results saved before 1.3.3: a tall box never sets a heading-sized line.
        item.lineHeight = nil; item.rows = 1; item.box.height = 0.2
        placement = ImageTranslationLayout.placement(of: item, in: size)
        XCTAssertEqual(placement.line, 32); XCTAssertFalse(placement.single); XCTAssertNil(placement.pitch)
        item.box.height = 0.025
        placement = ImageTranslationLayout.placement(of: item, in: size)
        XCTAssertEqual(placement.line, 25, accuracy: 1e-9); XCTAssertTrue(placement.single)
        // At the canvas edge the tile is clipped, never moved.
        item.box.x = 0
        XCTAssertEqual(ImageTranslationLayout.placement(of: item, in: size).tile.minX, 0)
    }

    func testOnlyClearSingleLinesAreCentredOrRightAligned() throws {
        let size = CGSize(width: 400, height: 1000)
        func placed(_ box: OCRTextBox, rows: Int = 1, vertical: Bool = false) -> ImageTranslationLayout.Alignment {
            let item = ImageTranslationLayout.Item(blockID: 1, cell: 0, text: "译文", original: "source", box: box,
                vertical: vertical, heading: false, lineHeight: box.height / Double(rows), rows: rows,
                alignment: ImageTranslationLayout.alignment(of: box))
            return ImageTranslationLayout.placement(of: item, in: size).alignment
        }
        XCTAssertEqual(placed(.init(x: 0.35, y: 0.9, width: 0.3, height: 0.03)), .center)
        XCTAssertEqual(placed(.init(x: 0.75, y: 0.5, width: 0.2, height: 0.03)), .trailing)
        XCTAssertEqual(placed(.init(x: 0.05, y: 0.5, width: 0.2, height: 0.03)), .leading)
        // A nearly full-width line is ordinary left-aligned text.
        XCTAssertEqual(placed(.init(x: 0.1, y: 0.5, width: 0.8, height: 0.03)), .leading)
        // Paragraphs and vertical columns keep their leading edge.
        XCTAssertEqual(placed(.init(x: 0.35, y: 0.5, width: 0.3, height: 0.09), rows: 3), .leading)
        XCTAssertEqual(placed(.init(x: 0.48, y: 0.3, width: 0.04, height: 0.4), vertical: true), .leading)

        // The menu fixture: the item keeps its left edge, the price its right edge.
        let lines: [RecognizedLine] = [.init(text: "Coffee", x: 0.05, y: 0.5, width: 0.2, height: 0.03, confidence: 1),
                                       .init(text: "450 yen", x: 0.75, y: 0.5, width: 0.2, height: 0.03, confidence: 1)]
        let sources = OCRLayout.readingBlocks(lines)
        let translated = try ProfessionalLayout(sources[0].text, readingBlocks: sources)
            .restoreBlocks(#"{"blocks":[{"id":1,"text":"咖啡450日元"}]}"#)
        let items = ImageTranslationLayout.items(in: .init(original: "", translated: "", sourceLanguages: "英语", target: "中文",
                                                           engine: "fixture", elapsed: 0, blocks: translated))
        XCTAssertEqual(items.map(\.alignment), [.leading, .trailing])
        XCTAssertEqual(items.map(\.rows), [1, 1])
        XCTAssertEqual(try XCTUnwrap(items.first?.lineHeight), 0.03, accuracy: 1e-9)
    }

    private func picture(width: Int = 300, height: Int = 200, background: (CGFloat, CGFloat, CGFloat),
                         ink: (CGFloat, CGFloat, CGFloat), text: CGRect) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: background.0, green: background.1, blue: background.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Vertical strokes stand in for glyphs; CoreGraphics' origin is the
        // bottom-left corner, like Vision's.
        context.setFillColor(red: ink.0, green: ink.1, blue: ink.2, alpha: 1)
        var x = text.minX + 2
        while x < text.maxX - 3 { context.fill(CGRect(x: x, y: text.minY + 2, width: 3, height: text.height - 4)); x += 6 }
        return context.makeImage()!
    }

    func testPaletteTakesBackgroundAndTextColourFromTheScreenshot() throws {
        // Text in the upper half: a flipped reading would find no strokes.
        let image = picture(background: (229 / 255, 229 / 255, 234 / 255), ink: (10 / 255, 61 / 255, 145 / 255),
                            text: CGRect(x: 50, y: 120, width: 200, height: 40))
        let box = OCRTextBox(x: 50.0 / 300, y: 0.6, width: 200.0 / 300, height: 0.2)
        let pixels = try XCTUnwrap(ImageOverlayPalette.Pixels(image: image))
        let palette = try XCTUnwrap(ImageOverlayPalette.sample(pixels, box: box, line: 0.2, vertical: false))
        XCTAssertEqual(palette.background.red * 255, 229, accuracy: 3); XCTAssertEqual(palette.background.blue * 255, 234, accuracy: 3)
        XCTAssertEqual(palette.ink.red * 255, 10, accuracy: 3); XCTAssertEqual(palette.ink.green * 255, 61, accuracy: 3)
        XCTAssertEqual(palette.ink.blue * 255, 145, accuracy: 3)
        let below = OCRTextBox(x: 50.0 / 300, y: 0.2, width: 200.0 / 300, height: 0.2)
        XCTAssertEqual(ImageOverlayPalette.sample(pixels, box: below, line: 0.2, vertical: false)?.ink, palette.background.foreground)

        // The same image read back from encoded data, as the app and the shortcut do.
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let decoded = try XCTUnwrap(ImageOverlayPalette.Pixels(data: data as Data))
        XCTAssertEqual(ImageOverlayPalette.sample(decoded, box: box, line: 0.2, vertical: false), palette)
        XCTAssertNotEqual(decoded, pixels, "Each copy of the pixels is its own image")
    }

    func testFaintTextIsDarkenedUntilItIsReadable() throws {
        let image = picture(background: (1, 1, 1), ink: (221 / 255, 221 / 255, 221 / 255), text: CGRect(x: 50, y: 120, width: 200, height: 40))
        let pixels = try XCTUnwrap(ImageOverlayPalette.Pixels(image: image))
        let palette = try XCTUnwrap(ImageOverlayPalette.sample(pixels, box: .init(x: 50.0 / 300, y: 0.6, width: 200.0 / 300, height: 0.2),
                                                               line: nil, vertical: false))
        XCTAssertGreaterThanOrEqual(palette.ink.contrast(with: palette.background), 4.5)
        XCTAssertGreaterThan(palette.background.luminance, 0.95)
        // Large screenshots are read at a bounded size.
        let reduced = try XCTUnwrap(ImageOverlayPalette.Pixels(image: image, maximumPixels: 15_000))
        XCTAssertEqual(reduced.width, 150); XCTAssertEqual(reduced.height, 100)
    }

    func testLineMetricsSurviveTranslationHistoryAndReview() throws {
        let box = OCRTextBox(x: 0.1, y: 0.6, width: 0.7, height: 0.06)
        let source = ReadingBlock(id: 1, text: "Coffee is freshly made", sourceBox: box, sourceLineHeight: 0.02, sourceLineCount: 2)
        let translated = try ProfessionalLayout(source.text, readingBlocks: [source])
            .restoreBlocks(#"{"blocks":[{"id":1,"text":"咖啡现做"}]}"#)
        XCTAssertEqual(translated.first?.sourceLineHeight, 0.02); XCTAssertEqual(translated.first?.sourceLineCount, 2)
        let value = TranslationResult(original: source.text, translated: "咖啡现做", sourceLanguages: "英语", target: "中文",
                                      engine: "fixture", elapsed: 0, blocks: translated)
        let decoded = try JSONDecoder().decode(TranslationResult.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded.blocks?.first?.sourceLineCount, 2)
        XCTAssertEqual(TranslationReview.sourceBlocks(in: decoded).first?.sourceLineHeight, 0.02)
        // A corrected block built from the box alone keeps the block's line metrics.
        let replacement = ReadingBlock(id: 1, text: "咖啡是现做的", original: "Coffee is freshly made", sourceBox: box)
        let updated = try TranslationReview.replacing(in: decoded, blockID: 1, with: replacement)
        XCTAssertEqual(updated.blocks?.first?.sourceLineHeight, 0.02); XCTAssertEqual(updated.blocks?.first?.sourceLineCount, 2)

        // History saved before 1.3.3 has neither key.
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [String: Any]
        object.removeValue(forKey: "sourceLineHeight"); object.removeValue(forKey: "sourceLineCount")
        let old = try JSONDecoder().decode(ReadingBlock.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.sourceLineHeight); XCTAssertNil(old.sourceLineCount); XCTAssertEqual(old.sourceBox, box)
    }

    func testPromptKeepsEachBlocksWordsOverThatBlock() {
        XCTAssertTrue(ProfessionalLayout.instructions.contains("Never move words, clauses or numbers into a neighbouring block"))
        XCTAssertTrue(ProfessionalLayout.instructions.contains("never merge across blocks"))
        XCTAssertTrue(TranslationPrompts.revision.contains("1.3.3"), "Cached translations made with the old prompt are not reused")
    }
}
