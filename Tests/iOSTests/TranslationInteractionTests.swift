import XCTest
import WebKit
@testable import ScreenTranslate

@MainActor
final class TranslationInteractionTests: XCTestCase {
    private func context() throws -> (SettingsStore, TranslationPipeline) {
        let suite = "ScreenTranslate.Interaction.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let keychain = KeychainStore(service: suite)
        let store = SettingsStore(defaults: defaults, directory: directory, keychain: keychain)
        var settings = AppSettings(); settings.provider = .custom; settings.cacheTranslations = true
        settings.configuration.baseURL = "https://mock.test/v1"
        settings.configuration.model = suite
        try store.save(settings, keys: [AIProvider.custom.rawValue: "fixture-key"])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        addTeardownBlock {
            session.invalidateAndCancel(); StubURLProtocol.registry.set(nil)
            defaults.removePersistentDomain(forName: suite)
            try? keychain.write("", provider: .custom); try? FileManager.default.removeItem(at: directory)
        }
        return (store, TranslationPipeline(client: APIClient(session: session)))
    }

    private nonisolated static func response(_ value: String) throws -> (Int, Data) {
        (200, try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": value], "finish_reason": "stop"]]]))
    }

    private func waitForIdle(_ model: TranslationViewModel) async throws {
        for _ in 0..<200 where model.busy { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(model.busy)
    }

    func testExplicitRetryBypassesCacheAndFailurePreservesReadableResult() async throws {
        let (store, pipeline) = try context()
        StubURLProtocol.registry.set { _ in try Self.response("第一份译文。") }
        let model = TranslationViewModel(store: store, pipeline: pipeline)
        model.text = "Read this paragraph."; model.translate(); try await waitForIdle(model)
        let before = try XCTUnwrap(model.result)
        let calls = RequestCounter()
        StubURLProtocol.registry.set { _ in calls.increment(); return (503, Data()) }
        model.translate(forceRefresh: true)
        XCTAssertEqual(model.result, before, "Retry keeps the previous result visible")
        try await waitForIdle(model)
        XCTAssertEqual(calls.value, 1, "Explicit retry must not replay the cached response")
        XCTAssertEqual(model.result, before); XCTAssertNotNil(model.error)
        XCTAssertEqual(store.history, [before]); XCTAssertTrue(store.settings.cacheTranslations)
        StubURLProtocol.registry.set { _ in calls.increment(); return try Self.response("更新后的译文。") }
        model.translate(forceRefresh: true); try await waitForIdle(model)
        XCTAssertEqual(calls.value, 2); XCTAssertEqual(model.result?.translated, "更新后的译文。")
        XCTAssertNil(model.error); XCTAssertEqual(store.history.count, 2)
        model.invalidateTranslation(); model.translate(); try await waitForIdle(model)
        XCTAssertEqual(model.result?.translated, "更新后的译文。")
        XCTAssertEqual(model.result?.usedCache, true); XCTAssertEqual(calls.value, 2)
    }

    func testCancelRetryPreservesPreviousResultAndIgnoresLateCompletion() async throws {
        let (store, pipeline) = try context()
        StubURLProtocol.registry.set { _ in try Self.response("保留这一份译文。") }
        let model = TranslationViewModel(store: store, pipeline: pipeline)
        model.text = "Keep this paragraph."; model.translate(); try await waitForIdle(model)
        let before = try XCTUnwrap(model.result)
        let calls = RequestCounter()
        StubURLProtocol.registry.set { _ in
            calls.increment(); Thread.sleep(forTimeInterval: 0.2)
            return try Self.response("不应该出现的过期译文。")
        }
        model.translate(forceRefresh: true); model.translate(forceRefresh: true)
        for _ in 0..<50 where calls.value == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(calls.value, 1, "Repeated taps cannot start overlapping translations")
        model.cancel()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertFalse(model.busy); XCTAssertFalse(model.isTranslating)
        XCTAssertEqual(model.result, before); XCTAssertEqual(store.history, [before])
        XCTAssertNil(model.error)
    }

    func testCancelledRequestCannotOverwriteNewInputOrSaveAnOldResult() async throws {
        let (store, pipeline) = try context()
        let calls = RequestCounter()
        StubURLProtocol.registry.set { _ in
            calls.increment(); Thread.sleep(forTimeInterval: 0.15)
            return try Self.response("已取消的译文。")
        }
        let model = TranslationViewModel(store: store, pipeline: pipeline)
        model.text = "Old input."; model.translate()
        for _ in 0..<50 where calls.value == 0 { try await Task.sleep(for: .milliseconds(10)) }
        model.clear(); model.text = "New input."
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(model.text, "New input."); XCTAssertNil(model.result)
        XCTAssertTrue(store.history.isEmpty); XCTAssertFalse(model.busy)
    }

    func testPastingNewContentInvalidatesResultAndLeavesItReadyForManualTranslation() async throws {
        let (store, pipeline) = try context()
        let calls = RequestCounter()
        StubURLProtocol.registry.set { _ in calls.increment(); return try Self.response("先前的译文。") }
        let model = TranslationViewModel(store: store, pipeline: pipeline)
        model.text = "Previous input."; model.translate(); try await waitForIdle(model)
        XCTAssertNotNil(model.result)
        model.paste([NSItemProvider(object: "A newly pasted paragraph." as NSString)])
        try await waitForIdle(model)
        XCTAssertNil(model.result); XCTAssertEqual(model.text, "A newly pasted paragraph.")
        XCTAssertEqual(calls.value, 1, "Pasting previews input without automatically sending it")
    }

    func testCancelledShortcutCannotStoreAResult() async throws {
        let (store, pipeline) = try context()
        let calls = RequestCounter()
        StubURLProtocol.registry.set { _ in
            calls.increment(); Thread.sleep(forTimeInterval: 0.15)
            return try Self.response("不应保存的快捷指令结果。")
        }
        let task = Task { try await IntentTranslationWork.text("Cancelled shortcut.", store: store, pipeline: pipeline) }
        for _ in 0..<50 where calls.value == 0 { try await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        do { _ = try await task.value; XCTFail("A cancelled shortcut must not return a success value") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertTrue(store.history.isEmpty)
    }

    func testQuickLookReaderFitsNarrowScreenAndOriginalFollowsTranslation() async throws {
        let blocks: [ReadingBlock] = [
            .init(id: 1, text: "日本語の読み方", kind: .heading),
            .init(id: 2, text: "今日、学校で日本語の文章を読みます。", kind: .paragraph),
            .init(id: 3, text: "• 新しい言葉を覚える。", kind: .listItem),
            .init(id: 4, text: "商品\t料金\t数量\t説明\t備考", kind: .tableHeader),
            .init(id: 5, text: "紅茶\t三百円\t二\t温かい飲み物\t無料", kind: .tableRow)]
        let value = TranslationResult(original: "Original text <script>source</script>", translated: blocks.map(\.text).joined(separator: "\n\n"),
            sourceLanguages: "英语", target: "日语", engine: "fixture", elapsed: 0.1, blocks: blocks)
        var settings = AppSettings(); settings.reader.showJapaneseFurigana = true
        let html = String(decoding: TranslationDocument.html(value, settings: settings), as: UTF8.self)
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 700))
        let loaded = expectation(description: "Reader loaded")
        let observer = InteractionNavigationObserver { loaded.fulfill() }
        web.navigationDelegate = observer; web.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        let metrics = try await web.evaluateJavaScript("""
        (() => {
          const main=document.querySelector('main'), original=document.querySelector('.original');
          const label=document.querySelector('label'), table=document.querySelector('.table-scroll');
          return {width:document.documentElement.scrollWidth, viewport:innerWidth,
            after:!!(main.compareDocumentPosition(original)&Node.DOCUMENT_POSITION_FOLLOWING),
            original:original.querySelector('p').textContent, hit:label.getBoundingClientRect().height,
            tableScroll:table.scrollWidth>table.clientWidth, ruby:getComputedStyle(document.querySelector('rt')).display};
        })()
        """) as! [String: Any]
        XCTAssertLessThanOrEqual(metrics["width"] as! Double, (metrics["viewport"] as! Double) + 1)
        XCTAssertEqual(metrics["after"] as? Bool, true); XCTAssertEqual(metrics["original"] as? String, value.original)
        XCTAssertGreaterThanOrEqual(metrics["hit"] as! Double, 44)
        XCTAssertEqual(metrics["tableScroll"] as? Bool, true); XCTAssertNotEqual(metrics["ruby"] as? String, "none")
        let open = try await web.evaluateJavaScript("document.querySelector('summary').click(); document.querySelector('.original').open")
        XCTAssertEqual(open as? Bool, true)
        let image = try await web.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: image); attachment.name = "快捷指令全文窗口-320pt"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}

@MainActor private final class InteractionNavigationObserver: NSObject, WKNavigationDelegate {
    let loaded: () -> Void
    init(loaded: @escaping () -> Void) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded() }
}
