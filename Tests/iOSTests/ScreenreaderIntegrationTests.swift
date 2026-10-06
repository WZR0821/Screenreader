import XCTest
import WebKit
@testable import ScreenTranslate

final class ScreenreaderIntegrationTests: XCTestCase {
    @MainActor func testModePromptsPersistAndIntentSnapshotsUseTheRequestedMode() throws {
        let suite = "Screenreader.Profiles.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let keychain = KeychainStore(service: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
            try? keychain.write("", provider: .custom)
        }
        let store = SettingsStore(defaults: defaults, directory: directory, keychain: keychain)
        var settings = store.settings; settings.provider = .custom
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "saved-model"
        settings.setPrompt("Brief labels.", for: .quick)
        settings.setPrompt("Keep tables.", for: .professional)
        settings.setPrompt("Describe the scene.", for: .visual)
        try store.save(settings, keys: ["custom": "fixture-key"])
        let reloaded = SettingsStore(defaults: defaults, directory: directory, keychain: keychain)
        for mode in TranslationMode.allCases {
            let (snapshot, key) = try reloaded.credentials(for: mode)
            XCTAssertEqual(snapshot.mode, mode)
            XCTAssertEqual(snapshot.customPrompt, settings.prompt(for: mode))
            XCTAssertEqual(snapshot.configuration.model, "saved-model")
            XCTAssertEqual(key, "fixture-key")
        }
        var changed = reloaded.settings; changed.setPrompt("", for: .professional)
        try reloaded.save(changed, keys: [:])
        XCTAssertEqual(try reloaded.credentials(for: .quick).0.customPrompt, "Brief labels.")
        XCTAssertEqual(try reloaded.credentials(for: .professional).0.customPrompt, "")
        XCTAssertEqual(try reloaded.credentials(for: .visual).0.customPrompt, "Describe the scene.")
    }

    @MainActor func testSavingRejectsOversizedInactivePromptWithoutLosingSettings() throws {
        let suite = "Screenreader.PromptLimit.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, keychain: KeychainStore(service: suite))
        var settings = store.settings
        settings.setPrompt(String(repeating: "x", count: 8001), for: .visual)
        XCTAssertThrowsError(try store.save(settings, keys: [:])) { XCTAssertEqual($0 as? TranslationError, .tooMuchPrompt) }
        XCTAssertEqual(store.settings, AppSettings())
        settings.setPrompt(String(repeating: "x", count: 8000), for: .visual)
        try store.save(settings, keys: [:])
        XCTAssertEqual(store.settings.prompt(for: .visual).count, 8000)
    }

    func testFullReaderDeclaresEverySelectedLanguageAndKeepsLastItem() {
        for target in TargetLanguage.allCases {
            let result = TranslationResult(original: "Original", translated: "First\n\nLast item", sourceLanguages: "English", target: target.title, engine: "fixture", elapsed: 0.1)
            let html = String(decoding: TranslationDocument.html(result), as: UTF8.self)
            let code = target == .english ? "en" : (target == .japanese ? "ja" : "zh-Hans")
            XCTAssertTrue(html.contains("<html lang=\"\(code)\""))
            XCTAssertTrue(html.contains("Last item")); XCTAssertTrue(html.contains("<summary>查看原文</summary>"))
            XCTAssertFalse(html.contains("fixture"), "Diagnostics must not fill the reading area")
        }
    }
}

final class RefinementReaderTests: XCTestCase {
    @MainActor func testEnglishReaderPreservesHierarchySymbolsPricesAndFinalLineAtLargeSize() async throws {
        let result = TranslationResult(original: "Sample menu", translated: "", sourceLanguages: "日语", target: "英语", engine: "fixture", elapsed: 0,
            blocks: [.init(id: 1, text: "Lunch menu", kind: .heading),
                .init(id: 2, text: "Freshly prepared. Choose one drink.", kind: .paragraph),
                .init(id: 3, text: "Double cheeseburger set: ¥1,100", kind: .field),
                .init(id: 4, text: "⚠️ Contains nuts", kind: .listItem),
                .init(id: 5, text: "1. Water", kind: .listItem),
                .init(id: 6, text: "2. Tea", kind: .listItem),
                .init(id: 7, text: "1.5 kg · 2026/10/06 · Thanks ❤️", kind: .paragraph),
                .init(id: 8, text: "Final note: no substitutions.", kind: .paragraph)])
        var settings = AppSettings(); settings.reader.textSize = .large
        let html = String(decoding: TranslationDocument.html(result, settings: settings), as: UTF8.self)
        XCTAssertTrue(result.blocks![3].hasVisibleListMarker)
        let sourceAttachment = XCTAttachment(string: html); sourceAttachment.name = "build17-reader-html"; sourceAttachment.lifetime = .keepAlways; add(sourceAttachment)
        XCTAssertTrue(html.contains("<li class=\"numbered\">⚠️ Contains nuts</li>"), html)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 760))
        let ready = expectation(description: "Full reader loaded")
        let delegate = RefinementReaderObserver { ready.fulfill() }; view.navigationDelegate = delegate
        view.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [ready], timeout: 10)
        let stats = try await view.evaluateJavaScript("""
        (() => ({width:document.documentElement.scrollWidth, viewport:innerWidth,
          heading:document.querySelector('h1').textContent,
          headingSize:parseFloat(getComputedStyle(document.querySelector('h1')).fontSize),
          bodySize:parseFloat(getComputedStyle(document.querySelector('main>p')).fontSize),
          marked:[...document.querySelectorAll('li.numbered')].map(x=>x.textContent),
          price:document.querySelector('.field-value').textContent,
          last:document.querySelector('main').lastChild.textContent,
          summary:document.querySelector('summary').textContent,
          paragraphs:[...document.querySelectorAll('main>p')].map(x=>x.textContent)}))()
        """) as! [String: Any]
        XCTAssertLessThanOrEqual(stats["width"] as! Double, (stats["viewport"] as! Double) + 1)
        XCTAssertGreaterThan(stats["headingSize"] as! Double, stats["bodySize"] as! Double)
        XCTAssertEqual(stats["marked"] as! [String], ["⚠️ Contains nuts", "1. Water", "2. Tea"])
        XCTAssertEqual(stats["price"] as? String, "¥1,100")
        XCTAssertEqual(stats["last"] as? String, "Final note: no substitutions.")
        XCTAssertEqual(stats["summary"] as? String, "查看原文")
        XCTAssertTrue((stats["paragraphs"] as! [String]).contains("1.5 kg · 2026/10/06 · Thanks ❤️"))
        let image = try await view.takeSnapshot(configuration: nil)
        let attachment = XCTAttachment(image: image); attachment.name = "build17-English-reader-320-large"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
private final class RefinementReaderObserver: NSObject, WKNavigationDelegate {
    let done: () -> Void
    init(_ done: @escaping () -> Void) { self.done = done }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done() }
}
