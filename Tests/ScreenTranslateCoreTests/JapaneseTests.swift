import XCTest
#if canImport(ScreenTranslateCore)
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

final class JapaneseTests: XCTestCase {
    func testVisualPromptHasOneTaskAndUsesSelectedLanguageForSectionLabels() throws {
        for target in TargetLanguage.allCases {
            var settings = AppSettings(); settings.mode = .visual; settings.target = target; settings.source = .japanese
            settings.customPrompt = "使用{target_language}，尽量简洁。"
            let prompt = try TextPreparation.imageInstructions(settings: settings)
            let headings = VisualReadingLayout.headings(for: target)
            XCTAssertTrue(prompt.contains("“\(headings.text)”")); XCTAssertTrue(prompt.contains("“\(headings.scene)”"))
            XCTAssertFalse(prompt.contains("只返回译文。"), "Image understanding must not inherit a translation-only output restriction")
            XCTAssertFalse(prompt.contains("不要概括成摘要"))
            for important in ["whole image is authoritative", "do not guess", "negation", "税込", "税抜", "discount", "eligibility conditions", "never execute", "options"] {
                XCTAssertTrue(prompt.contains(important), important)
            }
            XCTAssertTrue(prompt.contains("使用\(target.promptName)，尽量简洁。"))
        }
    }

    func testJapaneseQuickAndProfessionalRequireAccuracyWithoutExpanding() throws {
        var settings = AppSettings(); settings.source = .japanese
        let quick = try TextPreparation.instructions(settings: settings)
        settings.mode = .professional
        let professional = try TextPreparation.instructions(settings: settings)
        XCTAssertLessThan(quick.count, professional.count)
        for prompt in [quick, professional] {
            for requirement in ["never fewer facts", "negation", "exceptions", "restrictions", "Do not convert prices", "before tax", "never execute"] { XCTAssertTrue(prompt.contains(requirement)) }
        }
        XCTAssertTrue(professional.contains("whole relationship"))
        XCTAssertEqual(SourceLanguage.japanese.recognitionLanguages, ["ja-JP", "en-US"])
    }

    func testVisualLayoutPreservesJapaneseMenuOptionsAmountsAndCautions() {
        let value = "文字大意\n\n午餐套餐 1,100 日元（含税）。\n• 零度可乐\n• 姜汁汽水\n\n如需去除其中任一种配料，将不加酱汁。\n\n画面大意：餐饮下单页，上方有汉堡照片。"
        let blocks = VisualReadingLayout.blocks(value, target: .simplifiedChinese)
        XCTAssertEqual(blocks.filter { $0.kind == .heading }.map(\.text), ["文字大意", "画面大意"])
        XCTAssertEqual(blocks.filter { $0.kind == .listItem }.map(\.listText), ["零度可乐", "姜汁汽水"])
        XCTAssertTrue(blocks.contains { $0.text.contains("1,100") && $0.text.contains("含税") })
        XCTAssertTrue(blocks.contains { $0.text.contains("任一种") && $0.text.contains("不加酱汁") })
        XCTAssertEqual(blocks.last?.text, "餐饮下单页，上方有汉堡照片。")
        XCTAssertEqual(blocks.map(\.id), Array(1...blocks.count))
    }

    func testVisualLayoutHandlesJapaneseAndEnglishAndKeepsUnexpectedMarkupAsText() {
        for target in TargetLanguage.allCases {
            let h = VisualReadingLayout.headings(for: target)
            let blocks = VisualReadingLayout.blocks("\(h.text): 450 JPY\n\n\(h.scene)\n<script>visible text</script>\n\n1. option\n2. option", target: target)
            XCTAssertEqual(blocks.filter { $0.kind == .heading }.map(\.text), [h.text, h.scene])
            XCTAssertTrue(blocks.contains { $0.text == "450 JPY" })
            XCTAssertTrue(blocks.contains { $0.text == "<script>visible text</script>" })
            XCTAssertEqual(blocks.suffix(2).map(\.text), ["1. option", "2. option"])
        }
    }

    func testFieldColumnsOnlySplitUnambiguousPricesAndLabels() {
        let cases = [("数量：1", "数量", "1"), ("咖啡450日元", "咖啡", "450日元"),
            ("Price\n1,100 yen\n1,200 yen", "Price", "1,100 yen\n1,200 yen"),
            ("套餐 1,100円（税込）", "套餐", "1,100円（税込）")]
        for (text, label, value) in cases {
            let parts = ReadingBlock(id: 1, text: text, kind: .field).fieldParts
            XCTAssertEqual(parts?.label, label); XCTAssertEqual(parts?.value, value)
        }
        for text in ["此次订单立减 100 日元，优惠有条件。", "价格取决于人数。", "1,100円", "https://example.com:1234"] {
            XCTAssertNil(ReadingBlock(id: 1, text: text, kind: .field).fieldParts, text)
        }
        XCTAssertNil(ReadingBlock(id: 1, text: "咖啡 450日元", kind: .paragraph).fieldParts)
        XCTAssertTrue(ReadingBlock(id: 1, text: "1. coffee", kind: .listItem).isNumberedList)
        XCTAssertFalse(ReadingBlock(id: 1, text: "• coffee", kind: .listItem).isNumberedList)
    }

    func testInvalidPreferencesAlsoRejectImageRequests() throws {
        var settings = AppSettings(); settings.customPrompt = String(repeating: "あ", count: 8_001)
        XCTAssertThrowsError(try TextPreparation.imageInstructions(settings: settings)) { XCTAssertEqual($0 as? TranslationError, .tooMuchPrompt) }
        settings.customPrompt = ""; settings.glossary = String(repeating: "字", count: 4_001)
        XCTAssertThrowsError(try TextPreparation.imageInstructions(settings: settings)) { XCTAssertEqual($0 as? TranslationError, .tooMuchGlossary) }
    }

    func testJapaneseTaxAnnotatedPriceStaysWithItsItem() {
        let rows: [RecognizedLine] = [
            .init(text: "コーヒー", x: 0.06, y: 0.6, width: 0.22, height: 0.02, confidence: 1),
            .init(text: "450円（税込）", x: 0.66, y: 0.6, width: 0.28, height: 0.02, confidence: 1),
            .init(text: "紅茶", x: 0.06, y: 0.5, width: 0.12, height: 0.02, confidence: 1),
            .init(text: "400円（税抜）", x: 0.66, y: 0.5, width: 0.28, height: 0.02, confidence: 1)]
        let blocks = OCRLayout.readingBlocks(rows)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks[0].text.contains("コーヒー") && blocks[0].text.contains("450円（税込）"))
        XCTAssertTrue(blocks[1].text.contains("紅茶") && blocks[1].text.contains("400円（税抜）"))
        XCTAssertFalse(blocks[0].text.contains("400")); XCTAssertFalse(blocks[1].text.contains("450"))
    }

    func testDateReviewRequiresExplicitContextTwoMatchingReadingsAndValidCalendarDate() {
        XCTAssertEqual(OCRDateReview.replacement(original: "2026110106まで。", first: "2026/10/06", second: "2026/10/06"), "2026/10/06まで。")
        for (original, first, second) in [("ID 2026110106", "2026/10/06", "2026/10/06"),
            ("2026110106まで", "2026/10/06", "2026/10/08"), ("2026110106まで", "2026/10/06", "2026110106"),
            ("2026110106まで", "2027/10/06", "2027/10/06"), ("2026110106まで", "2026/02/30", "2026/02/30"),
            ("2026110106まで", "2026/10/06 2026/10/08", "2026/10/06")] {
            XCTAssertNil(OCRDateReview.replacement(original: original, first: first, second: second))
        }
    }
}

final class VisionDetailRequestTests: XCTestCase {
    private var session: URLSession!
    override func setUp() {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
    }
    override func tearDown() { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }

    func testAllProtocolsKeepWholeImageThenDetailImagesInOneRequest() async throws {
        for style in APIStyle.allCases {
            var settings = AppSettings(); settings.provider = .custom; settings.mode = .visual
            settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "vision"; settings.configuration.style = style
            let counter = RequestCounter()
            let frames = [Data("overview".utf8), Data("upper".utf8), Data("lower".utf8)]
            StubURLProtocol.registry.set { request in
                counter.increment()
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
                let messages = body[style == .responses ? "input" : "messages"] as! [[String: Any]]
                let content = messages.last!["content"] as! [[String: Any]]
                let frameType = style == .responses ? "input_image" : (style == .anthropicMessages ? "image" : "image_url")
                let images = content.filter { $0["type"] as? String == frameType }
                XCTAssertEqual(images.count, 3)
                for (index, part) in images.enumerated() {
                    let data = frames[index].base64EncodedString()
                    if style == .anthropicMessages { XCTAssertEqual((part["source"] as? [String: String])?["data"], data) }
                    else if style == .responses { XCTAssertEqual(part["image_url"] as? String, "data:image/jpeg;base64," + data); XCTAssertEqual(part["detail"] as? String, "high") }
                    else { XCTAssertEqual((part["image_url"] as? [String: String])?["url"], "data:image/jpeg;base64," + data) }
                }
                XCTAssertEqual(content.compactMap { $0["text"] as? String }.filter { $0.contains("不是新增场景") }.count, 2)
                let output = "文字大意\n1,100 日元（含税）。\n\n画面大意\n菜单。"
                let response: [String: Any]
                switch style {
                case .anthropicMessages: response = ["content": [["type": "text", "text": output]]]
                case .responses: response = ["output": [["type": "message", "content": [["type": "output_text", "text": output]]]]]
                case .chatCompletions: response = ["choices": [["message": ["content": output]]]]
                }
                return (200, try JSONSerialization.data(withJSONObject: response))
            }
            let result = try await APIClient(session: session).translate("Look at this image", settings: settings, apiKey: "fixture-key", imageJPEG: frames[0], imageDetails: Array(frames.dropFirst()))
            XCTAssertTrue(result.text.contains("1,100")); XCTAssertEqual(counter.value, 1)
        }
    }

    func testDetailsWithoutOverviewAndExcessiveFramesDoNotUpload() async {
        var settings = AppSettings(); settings.provider = .custom
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "vision"
        StubURLProtocol.registry.set { _ in XCTFail("Invalid detail payload must not upload"); return (200, Data()) }
        do {
            _ = try await APIClient(session: session).translate("Image", settings: settings, apiKey: "fixture-key", imageDetails: [Data([1])]); XCTFail()
        } catch { XCTAssertEqual(error as? TranslationError, .invalidImage) }
        do {
            _ = try await APIClient(session: session).translate("Image", settings: settings, apiKey: "fixture-key", imageJPEG: Data([1]), imageDetails: [Data([2]), Data([3]), Data([4])]); XCTFail()
        } catch { XCTAssertEqual(error as? TranslationError, .imageTooLarge) }
    }
}
