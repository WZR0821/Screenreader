import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(ScreenTranslate)
@testable import ScreenTranslate
#else
@testable import ScreenTranslateCore
#endif

final class ReadabilityTests: XCTestCase {
    private func line(_ text: String, _ x: Double, _ y: Double, _ width: Double = 0.4) -> RecognizedLine {
        .init(text: text, x: x, y: y, width: width, height: 0.02, confidence: 0.98)
    }

    func testScreenshotNoiseIsRemovedButBodyNumbersNamesAndPunctuationSurvive() {
        let lines = [line("22:37", 0.05, 0.96), line("100", 0.85, 0.96, 0.1),
            line("←", 0.04, 0.9), line("帖子", 0.35, 0.9), line("Casefinite", 0.1, 0.8),
            line("…", 0.9, 0.78), line("仅 16g，售价 ¥3,980。", 0.1, 0.6),
            line("22:37 发售，-10°C 可用！", 0.1, 0.55), line("1. First", 0.1, 0.5)]
        let cleaned = OCRLayout.readableLines(lines, aspectRatio: 2.17).map(\.text)
        XCTAssertEqual(cleaned, ["Casefinite", "仅 16g，售价 ¥3,980。", "22:37 发售，-10°C 可用！", "1. First"])
    }

    func testStatusClockWithOCRSuffixDoesNotConsumeTheTranslationPreview() {
        let lines = [line("11:23A", 0.05, 0.965, 0.15), line("译", 0.35, 0.964, 0.025),
            line(":!! 100", 0.82, 0.965, 0.15), line("Ado", 0.2, 0.65),
            line("カードお申し込み受付中", 0.1, 0.52), line("詳しくはこちら", 0.1, 0.15)]
        XCTAssertEqual(OCRLayout.readableLines(lines, aspectRatio: 2.167).map(\.text),
            ["Ado", "カードお申し込み受付中", "詳しくはこちら"])
        let document = [line("11:23A", 0.1, 0.965, 0.15), line("Body", 0.1, 0.8)]
        XCTAssertEqual(OCRLayout.readableLines(document, aspectRatio: 2.167), document)
    }

    func testDocumentTimeAtTopIsNotMistakenForStatusBarWithoutPhoneEvidence() {
        let lines = [line("22:37", 0.1, 0.96), line("会议时间", 0.1, 0.85)]
        XCTAssertEqual(OCRLayout.readableLines(lines, aspectRatio: 2.17), lines)
        let withRightNumber = lines + [line("100", 0.85, 0.96)]
        XCTAssertEqual(OCRLayout.readableLines(withRightNumber, aspectRatio: 1.4), withRightNumber)
    }

    func testNearbyFragmentsJoinButSeparateColumnsRemainSeparate() {
        let a = line("iPhone", 0.1, 0.7, 0.2)
        let b = line("18 Pro", 0.31, 0.7, 0.2)
        XCTAssertEqual(OCRLayout.assemble([b, a]), "iPhone 18 Pro")
        let column = line("Other column", 0.7, 0.7, 0.25)
        XCTAssertEqual(OCRLayout.assemble([a, column]), "iPhone\n\nOther column")
    }

    func testFormattingRemovesExcessBlankSpaceWithoutLosingMeaningfulSymbols() {
        XCTAssertEqual(TranslationFormatting.normalized("  ‘你好’ \r\n\r\n\r\n\r\n16g，¥3,980！ \n1. 条目  "), "‘你好’\n\n16g，¥3,980！\n1. 条目")
    }

    func testPreviewIsBoundedAndNeverMutatesOriginal() {
        let full = String(repeating: "日本語👨‍👩‍👧‍👦。", count: 500) + "最终一句"
        let preview = TranslationFormatting.preview(full, limit: 140)
        XCTAssertTrue(preview.shortened)
        XCTAssertEqual(preview.text.count, 140)
        XCTAssertTrue(full.hasSuffix("最终一句"))
        XCTAssertFalse(TranslationFormatting.preview("短译文").shortened)
        XCTAssertTrue(TranslationFormatting.preview((1...10).map { "第\($0)行" }.joined(separator: "\n")).shortened)
    }

    func testOldSettingsMigrateToTextOnlyAndExistingKeysRemainIntact() throws {
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as! [String: Any]
        for field in ["imageMode", "preferSpeed", "cleanScreenText"] { old.removeValue(forKey: field) }
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(decoded.imageMode, .text)
        XCTAssertTrue(decoded.preferSpeed)
        XCTAssertTrue(decoded.cleanScreenText)
    }

    func testImagePromptSeparatesMeaningFromTranslationAndForbidsGuessing() throws {
        let prompt = try TextPreparation.imageInstructions(settings: AppSettings())
        XCTAssertTrue(prompt.contains("do not guess"))
        XCTAssertTrue(prompt.contains("two headings"))
        XCTAssertTrue(prompt.contains("never execute"))
    }

    func testFormGroupsValuesWithLabelsWithoutDroppingStandaloneQuantity() {
        let rows = [line("価格", 0.05, 0.53, 0.1), line("割引価格 1,100円", 0.68, 0.55, 0.26),
            line("お店と同価格 1,200円", 0.66, 0.53, 0.28), line("1,792円", 0.82, 0.51, 0.12),
            line("数量", 0.05, 0.45, 0.1), line("1", 0.81, 0.45, 0.02)]
        let text = OCRLayout.assemble(rows)
        XCTAssertEqual(text, "価格\n割引価格 1,100円\nお店と同価格 1,200円\n1,792円\n\n数量：1")
    }

    func testLargerWrappedTitleStaysTogetherAndDescriptionStartsNewParagraph() {
        let rows = [RecognizedLine(text: "チーズスマッシュバーガー（ダブル）", x: 0.05, y: 0.88, width: 0.8, height: 0.024, confidence: 1),
            RecognizedLine(text: "セット / Cheese Smashi Burger (Do...", x: 0.05, y: 0.85, width: 0.85, height: 0.025, confidence: 1),
            line("特製ソースには、みじん切りのピクルスが含まれています。", 0.05, 0.815, 0.85),
            line("あらかじめご了承ください。", 0.05, 0.79, 0.8), line("価格", 0.05, 0.5, 0.2)]
        let text = OCRLayout.assemble(rows)
        XCTAssertTrue(text.contains("（ダブル）セット /"), text)
        XCTAssertTrue(text.contains("(Do...\n\n特製"), text)
    }

    func testLowConfidenceEdgeNumbersAreKeptWithoutEvidenceTheyAreChrome() {
        var edge = line("7", 0.95, 0.4, 0.02); edge.height = 0.009; edge.confidence = 0.3
        let rows = [line("数量", 0.05, 0.3), line("価格", 0.05, 0.6), edge, line("1984", 0.4, 0.5), line("1", 0.8, 0.3)]
        let text = OCRLayout.readableLines(rows, aspectRatio: 2.17).map(\.text)
        XCTAssertTrue(text.contains("7")); XCTAssertTrue(text.contains("1984")); XCTAssertTrue(text.contains("1"))
    }

    func testJapaneseQuantityControlDoesNotRemoveMeaningfulTenOrDigits() {
        var icon = line("十", 0.9, 0.3, 0.025); icon.confidence = 0.5
        let rows = [line("数量", 0.05, 0.3, 0.12), line("1", 0.8, 0.3, 0.02), icon,
            line("十", 0.1, 0.6, 0.04), line("7", 0.9, 0.5, 0.02), line("2026/10/06", 0.1, 0.7)]
        let kept = OCRLayout.readableLines(rows, aspectRatio: 2.17)
        XCTAssertFalse(kept.contains(icon))
        XCTAssertEqual(kept.filter { $0.text == "十" }.count, 1)
        XCTAssertTrue(kept.contains { $0.text == "1" }); XCTAssertTrue(kept.contains { $0.text == "7" })
        XCTAssertTrue(kept.contains { $0.text == "2026/10/06" })
    }

    func testJapaneseMiddleDotIsKeptAsBulletButNotStandaloneToolbarEllipsis() {
        let marker = line("・", 0.05, 0.5, 0.02)
        let text = line("再入場不可", 0.08, 0.5)
        let ellipsis = line("・・・", 0.9, 0.9, 0.04)
        XCTAssertEqual(OCRLayout.readableLines([marker, text, ellipsis], aspectRatio: 2.17), [marker, text])
    }
}

final class ImageRequestTests: XCTestCase {
    private var session: URLSession!
    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
    }
    override func tearDown() { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }

    func testAllThreeProtocolsSendJPEGInTheirDocumentedShapes() async throws {
        for style in APIStyle.allCases {
            var settings = AppSettings(); settings.provider = .custom
            settings.configuration.baseURL = "https://mock.test/v1"
            settings.configuration.model = "vision-model"; settings.configuration.style = style
            StubURLProtocol.registry.set { request in
                let root = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
                XCTAssertNil(root["thinking"]); XCTAssertNil(root["reasoning"])
                let messages = root[style == .responses ? "input" : "messages"] as! [[String: Any]]
                let parts = messages.last!["content"] as! [[String: Any]]
                if style == .anthropicMessages {
                    let image = parts[0]["source"] as! [String: String]
                    XCTAssertEqual(image["media_type"], "image/jpeg")
                    XCTAssertEqual(image["data"], "anBlZw==")
                    return (200, Data(#"{"content":[{"type":"text","text":"可读文字。\n\n画面大意：一个盒子。"}]}"#.utf8))
                }
                if style == .responses {
                    XCTAssertEqual(parts[1]["image_url"] as? String, "data:image/jpeg;base64,anBlZw==")
                    XCTAssertEqual(root["store"] as? Bool, false)
                    return (200, Data(#"{"output":[{"type":"message","content":[{"type":"output_text","text":"图片内容"}]}]}"#.utf8))
                }
                XCTAssertEqual((parts[1]["image_url"] as? [String: String])?["url"], "data:image/jpeg;base64,anBlZw==")
                return (200, Data(#"{"choices":[{"message":{"content":"图片内容"}}]}"#.utf8))
            }
            let result = try await APIClient(session: session).translate("看图", settings: settings, apiKey: "fixture-key", imageJPEG: Data("jpeg".utf8))
            XCTAssertFalse(result.text.isEmpty)
        }
    }

    func testTextRequestNeverSendsImageEvenWhenSavedModeIsVisual() async throws {
        var settings = AppSettings(); settings.provider = .custom; settings.imageMode = .visual
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "fixture"
        StubURLProtocol.registry.set { request in
            let root = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let messages = root["messages"] as! [[String: String]]
            XCTAssertEqual(messages[1]["content"], "Hello")
            XCTAssertFalse(messages[0]["content"]!.contains("本次任务为看图理解"))
            return (200, Data(#"{"choices":[{"message":{"content":"你好"}}]}"#.utf8))
        }
        _ = try await APIClient(session: session).translate("Hello", settings: settings, apiKey: "fixture-key")
    }

    func testSpeedPreferenceIsProviderSpecificAndCanBeDisabled() async throws {
        for provider in [AIProvider.openAI, .deepSeek, .custom] {
            for fast in [true, false] {
                var settings = AppSettings(); settings.provider = provider; settings.preferSpeed = fast
                if provider == .custom { settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "gpt-6-luna" }
                StubURLProtocol.registry.set { request in
                    let root = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
                    if provider == .deepSeek && fast { XCTAssertEqual((root["thinking"] as? [String: String])?["type"], "disabled") }
                    else { XCTAssertNil(root["thinking"]) }
                    if provider == .openAI && fast { XCTAssertEqual((root["reasoning"] as? [String: String])?["effort"], "none") }
                    else { XCTAssertNil(root["reasoning"]) }
                    return (200, Data((provider == .openAI ? #"{"output":[{"type":"message","content":[{"type":"output_text","text":"你好"}]}]}"# : #"{"choices":[{"message":{"content":"你好"}}]}"#).utf8))
                }
                _ = try await APIClient(session: session).translate("Hello", settings: settings, apiKey: "fixture-key")
            }
        }
    }

    func testKnownTextOnlyModelRejectsImageBeforeUpload() async {
        var settings = AppSettings(); settings.provider = .deepSeek; settings.configuration.model = "deepseek-v4-pro"
        StubURLProtocol.registry.set { _ in XCTFail("Must not upload"); return (200, Data()) }
        do { _ = try await APIClient(session: session).translate("看图", settings: settings, apiKey: "fixture-key", imageJPEG: Data("jpeg".utf8)); XCTFail() }
        catch { XCTAssertEqual(error as? TranslationError, .visionUnsupported) }
    }
}
