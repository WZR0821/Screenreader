import XCTest
@testable import ScreenTranslate

/// A stand-in for a professional reply to one numbered block. The app takes
/// such a reply only with each table cell kept apart, empty cells still
/// empty and every number of the source block still there, so the fixed
/// sentence keeps those.
private func keepingNumbers(_ block: String, reply: String) -> String {
    let pattern = #"(?<![A-Za-z0-9])[-]?[0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?"#
    let regex = try! NSRegularExpression(pattern: pattern)
    return block.components(separatedBy: "\t").map { cell in
        guard !cell.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return cell }
        // Read the way ProfessionalLayout counts numbers.
        let digits = (cell.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? cell)
            .replacingOccurrences(of: "−", with: "-")
        let numbers = regex.matches(in: digits, range: NSRange(digits.startIndex..., in: digits))
            .compactMap { Range($0.range, in: digits).map { String(digits[$0]) } }
        return ([reply] + numbers).joined(separator: " ")
    }.joined(separator: "\t")
}

/// 1.4.0 (33): the action button reads a screenshot with Vision and follows
/// 语言优先级 the way typed text does, and 识图 explains the picture in the
/// language the text in it resolves to. The screenshots, a Chinese phone
/// showing Japanese, Chinese and English content, are in
/// Tests/Fixtures/screen-priority-v1.
@MainActor
final class Release140ScreenIntegrationTests: XCTestCase {
    private final class RequestLog: @unchecked Sendable {
        private let lock = NSLock()
        private var bodies: [String] = []
        func add(_ body: String) { lock.lock(); bodies.append(body); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return bodies }
        var last: String { all.last ?? "" }
    }

    private func context(target: TargetLanguage) throws -> (SettingsStore, TranslationPipeline, RequestLog) {
        let suite = "ScreenTranslate.ScreenPriority.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let keychain = KeychainStore(service: suite)
        let store = SettingsStore(defaults: defaults, directory: directory, keychain: keychain)
        var settings = AppSettings(); settings.provider = .custom; settings.target = target
        settings.configuration.baseURL = "https://mock.test/v1"; settings.configuration.model = suite
        try store.save(settings, keys: [AIProvider.custom.rawValue: "fixture-key"])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock {
            session.invalidateAndCancel(); StubURLProtocol.registry.set(nil)
            defaults.removePersistentDomain(forName: suite)
            try? keychain.write("", provider: .custom); try? FileManager.default.removeItem(at: directory)
        }
        // Answers in the language the request asks for, like a real provider:
        // numbered blocks for professional mode, plain text otherwise.
        let log = RequestLog()
        StubURLProtocol.registry.set { request in
            let data = requestBody(request)
            let whole = String(decoding: data, as: UTF8.self)
            log.add(whole)
            let reply = whole.contains("Translate every part into Japanese") || whole.contains("entirely in Japanese") ? "これはテスト用の訳文です。"
                : whole.contains("Translate every part into English") || whole.contains("entirely in English") ? "This is the test translation."
                : "这是测试用的译文。"
            let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            if let text = (body["messages"] as! [[String: Any]]).last?["content"] as? String {
                let numbered = (try? JSONDecoder().decode(ProfessionalLayout.Document.self, from: Data(text.utf8))) != nil
                return try imageLayoutResponse(request) { numbered ? keepingNumbers($0, reply: reply) : reply }
            }
            return (200, try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": reply], "finish_reason": "stop"]]]))
        }
        return (store, TranslationPipeline(client: APIClient(session: session)), log)
    }

    private func screenshot(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "png"), name)
        return try Data(contentsOf: url)
    }

    /// Does what the 读屏全文 shortcut does with a screenshot, and keeps what
    /// was read and decided with the test results.
    private func actionButton(_ name: String, store: SettingsStore, pipeline: TranslationPipeline,
                              mode: TranslationMode) async throws -> TranslationResult {
        let selected = store.settings.target
        let started = Date()
        let (result, _) = try await IntentTranslationWork.image(try screenshot(name), store: store, pipeline: pipeline, mode: mode)
        let record = try JSONSerialization.data(withJSONObject: [
            "case": name, "mode": mode.rawValue, "runtime": "iOS Simulator / Apple Vision / stubbed API",
            "selected": selected.title, "target": result.target, "note": result.targetNote ?? "",
            "seconds": Date().timeIntervalSince(started), "recognizedText": result.original,
        ], options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: record, uniformTypeIdentifier: "public.json")
        attachment.name = "1.4.0-\(name)-\(mode.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
        return result
    }

    func testTheActionButtonTranslatesJapaneseScreensIntoChinese() async throws {
        let (store, pipeline, log) = try context(target: .japanese)
        let cases: [(String, TranslationMode)] = [("ja-timeline-zh-ui", .quick), ("ja-chat-zh-ui", .quick),
                                                  ("ja-chat-sparse-zh-ui", .quick), ("ja-timeline-zh-ui", .professional)]
        for (name, mode) in cases {
            let result = try await actionButton(name, store: store, pipeline: pipeline, mode: mode)
            XCTAssertEqual(result.target, "中文", "\(name) \(mode): \(result.original)")
            XCTAssertEqual(result.targetNote, "原文是日语，已按语言优先级改译为中文。", name)
            XCTAssertTrue(result.translated.contains("这是测试用的译文。"), name)
            XCTAssertTrue(log.last.contains("Translate every part into Simplified Chinese"), name)
            XCTAssertTrue(log.last.contains("The source language is Japanese"), name)
            XCTAssertEqual(store.history.first?.targetNote, result.targetNote, name)
            // Quick Look shows the reason: the action button has no preview.
            let html = String(decoding: TranslationDocument.html(result), as: UTF8.self)
            XCTAssertTrue(html.contains("<div class=\"target-note\">原文是日语，已按语言优先级改译为中文。</div>"), name)
        }
        XCTAssertEqual(store.settings.target, .japanese, "The saved choice stays")
    }

    func testTheReadersOwnLanguageStillNeedsTheWholeScreen() async throws {
        let (store, pipeline, log) = try context(target: .simplifiedChinese)
        // A Chinese article goes to Japanese; the link under it is not English.
        let article = try await actionButton("zh-article", store: store, pipeline: pipeline, mode: .quick)
        XCTAssertEqual(article.target, "日语", article.original)
        XCTAssertEqual(article.targetNote, "原文是中文，已按语言优先级改译为日语。")
        XCTAssertTrue(log.last.contains("Translate every part into Japanese"))
        // The Japanese message in a Chinese group chat is why it was taken.
        let chat = try await actionButton("zh-chat-with-ja", store: store, pipeline: pipeline, mode: .quick)
        XCTAssertEqual(chat.target, "中文", chat.original); XCTAssertNil(chat.targetNote)
        XCTAssertTrue(log.last.contains("Translate every part into Simplified Chinese"))
        try store.change { $0.target = .japanese }
        let kept = try await actionButton("zh-chat-with-ja", store: store, pipeline: pipeline, mode: .quick)
        XCTAssertEqual(kept.target, "日语", kept.original); XCTAssertNil(kept.targetNote)
    }

    func testAnEnglishTimelineOnAChinesePhoneGoesToChinese() async throws {
        let (store, pipeline, log) = try context(target: .english)
        let result = try await actionButton("en-timeline-zh-ui", store: store, pipeline: pipeline, mode: .quick)
        XCTAssertEqual(result.target, "中文", result.original)
        XCTAssertEqual(result.targetNote, "原文是英语，已按语言优先级改译为中文。")
        XCTAssertTrue(log.last.contains("Translate every part into Simplified Chinese"))
    }

    func testVisualModeExplainsInTheResolvedLanguage() async throws {
        let (store, pipeline, log) = try context(target: .japanese)
        let result = try await actionButton("ja-chat-zh-ui", store: store, pipeline: pipeline, mode: .visual)
        XCTAssertEqual(result.imageMode, .visual)
        XCTAssertEqual(result.target, "中文", result.original)
        XCTAssertEqual(result.targetNote, "原文是日语，已按语言优先级改译为中文。")
        XCTAssertEqual(result.translated, "这是测试用的译文。")
        XCTAssertEqual(log.all.count, 1, "识图 is still one request")
        XCTAssertTrue(log.last.contains("Explain this image entirely in Simplified Chinese"))
        XCTAssertTrue(log.last.contains("overall scene in Simplified Chinese"), "The instructions say the same")
        XCTAssertFalse(log.last.contains("entirely in Japanese"))
        let html = String(decoding: TranslationDocument.html(result), as: UTF8.self)
        XCTAssertTrue(html.contains("<div class=\"target-note\">原文是日语，已按语言优先级改译为中文。</div>"))
        XCTAssertEqual(store.history.first?.targetNote, result.targetNote)
        // A Chinese chat with a Japanese message is explained as selected.
        try store.change { $0.target = .simplifiedChinese }
        let chat = try await actionButton("zh-chat-with-ja", store: store, pipeline: pipeline, mode: .visual)
        XCTAssertEqual(chat.target, "中文", chat.original); XCTAssertNil(chat.targetNote)
        XCTAssertTrue(log.last.contains("Explain this image entirely in Simplified Chinese"))
    }

    func testAChosenSourceLanguageOrTheSwitchTurnedOffKeepsTheTarget() async throws {
        let (store, pipeline, log) = try context(target: .japanese)
        try store.change { $0.smartTarget = false }
        let off = try await actionButton("ja-chat-zh-ui", store: store, pipeline: pipeline, mode: .quick)
        XCTAssertEqual(off.target, "日语"); XCTAssertNil(off.targetNote)
        XCTAssertTrue(log.last.contains("Translate every part into Japanese"))
        try store.change { $0.smartTarget = true; $0.source = .japanese }
        let chosen = try await actionButton("ja-chat-zh-ui", store: store, pipeline: pipeline, mode: .visual)
        XCTAssertEqual(chosen.target, "日语"); XCTAssertNil(chosen.targetNote)
        XCTAssertTrue(log.last.contains("Explain this image entirely in Japanese"))
    }
}
