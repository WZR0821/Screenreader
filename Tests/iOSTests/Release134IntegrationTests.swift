import XCTest
import WebKit
@testable import ScreenTranslate

/// 1.3.4: 语言优先级 reaches every way a text is translated, and only those.
@MainActor
final class Release134IntegrationTests: XCTestCase {
    private final class PromptLog: @unchecked Sendable {
        private let lock = NSLock()
        private var prompts: [String] = []
        func add(_ prompt: String) { lock.lock(); prompts.append(prompt); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return prompts }
    }

    private func context() throws -> (SettingsStore, TranslationPipeline, PromptLog) {
        let suite = "ScreenTranslate.Priority.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let keychain = KeychainStore(service: suite)
        let store = SettingsStore(defaults: defaults, directory: directory, keychain: keychain)
        var settings = AppSettings(); settings.provider = .custom
        settings.configuration.baseURL = "https://mock.test/v1"; settings.configuration.model = suite
        try store.save(settings, keys: [AIProvider.custom.rawValue: "fixture-key"])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock {
            session.invalidateAndCancel(); StubURLProtocol.registry.set(nil)
            defaults.removePersistentDomain(forName: suite)
            try? keychain.write("", provider: .custom); try? FileManager.default.removeItem(at: directory)
        }
        // Answers in the language the request asks for, like a real provider.
        let log = PromptLog()
        StubURLProtocol.registry.set { request in
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let prompt = (body["messages"] as! [[String: Any]])[0]["content"] as! String
            log.add(prompt)
            let reply = prompt.contains("Translate every part into Japanese") ? "これはいくらですか。"
                : prompt.contains("Translate every part into English") ? "How much is this?" : "这个多少钱？"
            return (200, try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": reply], "finish_reason": "stop"]]]))
        }
        return (store, TranslationPipeline(client: APIClient(session: session)), log)
    }

    private func waitForIdle(_ model: TranslationViewModel) async throws {
        for _ in 0..<200 where model.busy { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(model.busy)
    }

    func testTypedChineseGoesToJapaneseWhileTheSavedChoiceStays() async throws {
        let (store, pipeline, log) = try context()
        let model = TranslationViewModel(store: store, pipeline: pipeline)
        XCTAssertFalse(model.targetResolution(store.settings).switched, "An empty box shows the saved target")
        model.text = "这个东西多少钱？"
        let preview = model.targetResolution(store.settings)
        XCTAssertTrue(preview.switched); XCTAssertEqual(preview.settings.target, .japanese)
        model.translate(); try await waitForIdle(model)
        let result = try XCTUnwrap(model.result)
        XCTAssertNil(model.error)
        XCTAssertEqual(result.translated, "これはいくらですか。")
        XCTAssertEqual(result.target, "日语"); XCTAssertEqual(result.sourceLanguages, "中文")
        XCTAssertEqual(result.targetNote, "原文是中文，已按语言优先级改译为日语。")
        XCTAssertEqual(log.all.count, 1)
        XCTAssertTrue(log.all[0].contains("The source language is \(SourceLanguage.chinese.promptName)"), log.all[0])
        // The page shows what the user picked the next time, and the record explains itself.
        XCTAssertEqual(store.settings.target, .simplifiedChinese); XCTAssertEqual(store.settings.source, .automatic)
        XCTAssertEqual(store.history.first?.targetNote, result.targetNote)

        // The same text again comes from the cache, still in Japanese.
        model.invalidateTranslation(); model.translate(); try await waitForIdle(model)
        XCTAssertEqual(log.all.count, 1); XCTAssertEqual(model.result?.usedCache, true)
        XCTAssertEqual(model.result?.translated, "これはいくらですか。"); XCTAssertNotNil(model.result?.targetNote)
    }

    func testOtherLanguagesAndExplicitChoicesTranslateAsSelected() async throws {
        let (store, pipeline, log) = try context()
        let model = TranslationViewModel(store: store, pipeline: pipeline)
        for text in ["Good morning.", "今日は天気がいいですね。", "東京都"] {
            model.text = text
            XCTAssertFalse(model.targetResolution(store.settings).switched, text)
            model.translate(); try await waitForIdle(model)
            XCTAssertEqual(model.result?.target, "中文", text); XCTAssertNil(model.result?.targetNote, text)
            XCTAssertTrue(log.all.last?.contains("Translate every part into Simplified Chinese") == true, text)
        }
        // Switched off: Chinese is sent as before.
        try store.change { $0.smartTarget = false }
        model.text = "这个东西多少钱？"
        XCTAssertFalse(model.targetResolution(store.settings).switched)
        model.translate(); try await waitForIdle(model)
        XCTAssertEqual(model.result?.target, "中文"); XCTAssertNil(model.result?.targetNote)
        XCTAssertTrue(log.all.last?.contains("Translate every part into Simplified Chinese") == true)
        // Switched on again, but with the source language selected by hand.
        try store.change { $0.smartTarget = true; $0.source = .chinese }
        model.text = "这个东西要多少钱？"
        XCTAssertFalse(model.targetResolution(store.settings).switched)
        model.translate(); try await waitForIdle(model)
        XCTAssertEqual(model.result?.target, "中文"); XCTAssertNil(model.result?.targetNote)
        // 识图 explains a picture in the selected language.
        try store.change { $0.source = .automatic; $0.mode = .visual }
        XCTAssertFalse(model.targetResolution(store.settings).switched)
    }

    func testThePriorityOrderDecidesTheNewTarget() async throws {
        let (store, pipeline, log) = try context()
        try store.change { $0.languagePriority = [.english, .japanese, .simplifiedChinese] }
        let model = TranslationViewModel(store: store, pipeline: pipeline)
        model.text = "这个东西多少钱？"; model.translate(); try await waitForIdle(model)
        XCTAssertEqual(model.result?.target, "英语"); XCTAssertEqual(model.result?.translated, "How much is this?")
        XCTAssertEqual(model.result?.targetNote, "原文是中文，已按语言优先级改译为英语。")
        XCTAssertTrue(log.all.last?.contains("Translate every part into English") == true)
        // English typed with English as the target goes to the next one: Japanese.
        try store.change { $0.target = .english }
        model.text = "Good morning."; model.translate(); try await waitForIdle(model)
        XCTAssertEqual(model.result?.target, "日语"); XCTAssertEqual(model.result?.sourceLanguages, "英语")
    }

    func testScreenshotTextFollowsTheRuleButSharedKanjiStay() async throws {
        let (store, pipeline, log) = try context()
        let (settings, key) = try store.credentials()
        let chinese = OCRResult(text: "这个东西多少钱？\n欢迎光临", languages: "中文", lowConfidence: false)
        let switched = try await pipeline.recognizedText(chinese, settings: settings, key: key)
        XCTAssertEqual(switched.target, "日语"); XCTAssertEqual(switched.sourceLanguages, "中文")
        XCTAssertNotNil(switched.targetNote); XCTAssertEqual(switched.imageMode, .text)
        XCTAssertTrue(log.all.last?.contains("Translate every part into Japanese") == true)
        // 定休日 on a sign is as likely Japanese: translate it as selected.
        let shared = OCRResult(text: "定休日", languages: "自动识别", lowConfidence: false)
        let kept = try await pipeline.recognizedText(shared, settings: settings, key: key)
        XCTAssertEqual(kept.target, "中文"); XCTAssertNil(kept.targetNote)
        XCTAssertTrue(log.all.last?.contains("Translate every part into Simplified Chinese") == true)
        let japanese = OCRResult(text: "本日は定休日です。", languages: "日语", lowConfidence: false)
        let translated = try await pipeline.recognizedText(japanese, settings: settings, key: key)
        XCTAssertEqual(translated.target, "中文"); XCTAssertNil(translated.targetNote)
    }

    func testScreenshotWithAnotherLanguageInItIsTranslatedAsSelected() async throws {
        let (store, pipeline, log) = try context()
        let (settings, key) = try store.credentials()
        // A Chinese chat with one Japanese message. The message is why the
        // screenshot was taken, so everything goes into Chinese as selected.
        let chat = OCRResult(text: "王老师\n明天的会议改到几点了？\n我这边下午都有空，你们定好时间告诉我一声就行。\n"
            + "明日の会議は午後三時からです。よろしくお願いします。\n好的，谢谢！那我们明天见。", languages: "自动识别", lowConfidence: false)
        let kept = try await pipeline.recognizedText(chat, settings: settings, key: key)
        XCTAssertEqual(kept.target, "中文"); XCTAssertNil(kept.targetNote)
        XCTAssertTrue(log.all.last?.contains("Translate every part into Simplified Chinese") == true)
        // The same with an English sentence on a Chinese page.
        let page = OCRResult(text: "车票须知\n请妥善保管车票，出站时需要再次检票。\n遗失车票需要按全程票价补票。\n"
            + "Please keep this ticket until you leave the station.", languages: "自动识别", lowConfidence: false)
        let english = try await pipeline.recognizedText(page, settings: settings, key: key)
        XCTAssertEqual(english.target, "中文"); XCTAssertNil(english.targetNote)
        // Without the foreign sentence the same page is Chinese throughout.
        let plain = OCRResult(text: "车票须知\n请妥善保管车票，出站时需要再次检票。\n遗失车票需要按全程票价补票。",
                              languages: "中文", lowConfidence: false)
        let switched = try await pipeline.recognizedText(plain, settings: settings, key: key)
        XCTAssertEqual(switched.target, "日语"); XCTAssertNotNil(switched.targetNote)
    }

    func testFullTextWindowExplainsAChangedTarget() async throws {
        var result = TranslationResult(original: "这个东西多少钱？", translated: "これはいくらですか。",
            sourceLanguages: "中文", target: "日语", engine: "fixture", elapsed: 1, mode: .quick)
        XCTAssertFalse(String(decoding: TranslationDocument.html(result), as: UTF8.self).contains("class=\"target-note\""))
        result.targetNote = "原文是中文，已按语言优先级改译为日语。"
        let html = String(decoding: TranslationDocument.html(result), as: UTF8.self)
        XCTAssertTrue(html.contains("<div class=\"target-note\">原文是中文，已按语言优先级改译为日语。</div>"), "The action button has no preview")
        XCTAssertTrue(html.contains("中文 → 日语"))
        // Laid out as Quick Look shows it: the note sits between the header
        // and the translation, on one line, touching neither.
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 480))
        let loaded = expectation(description: "Reader loaded")
        let observer = NoteNavigationObserver { loaded.fulfill() }
        view.navigationDelegate = observer
        view.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 10)
        let layout = try await view.evaluateJavaScript("""
        (() => { const box = s => document.querySelector(s).getBoundingClientRect();
          const header = box('.reader-header'), note = box('.target-note'), main = box('main');
          return {headerBottom: header.bottom, noteTop: note.top, noteBottom: note.bottom, noteHeight: note.height,
            mainTop: main.top, width: document.documentElement.scrollWidth, viewport: window.innerWidth,
            font: getComputedStyle(document.querySelector('.target-note')).fontSize}; })()
        """) as! [String: Any]
        func value(_ key: String) -> Double { layout[key] as! Double }
        XCTAssertGreaterThanOrEqual(value("noteTop"), value("headerBottom"))
        XCTAssertLessThan(value("noteBottom"), value("mainTop"))
        XCTAssertLessThan(value("noteHeight"), 24, "One line at 390 pt")
        XCTAssertLessThanOrEqual(value("width"), value("viewport"))
        XCTAssertEqual(layout["font"] as? String, "13px")
        let screenshot = try await view.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: screenshot); attachment.name = "1.3.4-全文窗口里的改译说明"
        attachment.lifetime = .keepAlways; add(attachment)
    }

    func testShortcutTextFollowsTheRuleAndPlainPipelineCallsDoNot() async throws {
        let (store, pipeline, log) = try context()
        let (shortcut, _) = try await IntentTranslationWork.text("这个东西多少钱？", store: store, pipeline: pipeline, mode: .quick)
        XCTAssertEqual(shortcut.target, "日语"); XCTAssertEqual(shortcut.translated, "これはいくらですか。")
        XCTAssertNotNil(shortcut.targetNote)
        // Without an origin the pipeline translates exactly as told. Translating
        // one block of a finished result again relies on this.
        let (settings, key) = try store.credentials()
        let plain = try await pipeline.text("这个东西到底多少钱？", settings: settings, key: key)
        XCTAssertEqual(plain.target, "中文"); XCTAssertNil(plain.targetNote)
        XCTAssertTrue(log.all.last?.contains("Translate every part into Simplified Chinese") == true)
    }

    func testRetranslatingOneBlockKeepsTheLanguageOfItsResult() async throws {
        let (store, pipeline, _) = try context()
        let (settings, key) = try store.credentials()
        // An English screenshot translated into Chinese; the user then corrects
        // one block to Chinese text. It must stay with the Chinese result.
        let blocks: [ReadingBlock] = [
            .init(id: 1, text: "菜单", kind: .heading, original: "Menu"),
            .init(id: 2, text: "咖啡 450日元", kind: .field, original: "Coffee 450 yen")]
        let result = TranslationResult(original: "Menu\n\nCoffee 450 yen", translated: "菜单\n\n咖啡 450日元",
            sourceLanguages: "自动识别", target: "中文", engine: "fixture", elapsed: 1, mode: .professional, blocks: blocks)
        let seen = PromptLog()
        StubURLProtocol.registry.set { request in
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            seen.add((body["messages"] as! [[String: Any]])[0]["content"] as! String)
            let output = String(decoding: try JSONEncoder().encode(
                ProfessionalLayout.Document(blocks: [.init(id: 1, text: "咖啡 460日元")])), as: UTF8.self)
            return (200, try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": output], "finish_reason": "stop"]]]))
        }
        let block = try await pipeline.retranslateBlock(in: result, blockID: 2, correctedText: "这个咖啡多少钱？",
                                                        settings: settings, key: key)
        XCTAssertEqual(block.text, "咖啡 460日元")
        XCTAssertEqual(seen.all.count, 1)
        XCTAssertTrue(seen.all[0].contains("Simplified Chinese")); XCTAssertFalse(seen.all[0].contains("into Japanese"))
    }
}

@MainActor private final class NoteNavigationObserver: NSObject, WKNavigationDelegate {
    var completed: () -> Void
    init(_ completed: @escaping () -> Void) { self.completed = completed }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { completed() }
}
