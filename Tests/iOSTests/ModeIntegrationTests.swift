import XCTest
@testable import ScreenTranslate

@MainActor
final class ModeIntegrationTests: XCTestCase {
    func testShortcutOverrideUsesAPIAndDoesNotChangeDefaultOrEngine() async throws {
        let suite = "ScreenTranslate.ModeTest.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainStore(service: suite)
        defer { defaults.removePersistentDomain(forName: suite); try? keychain.write("", provider: .custom) }
        let store = SettingsStore(defaults: defaults, keychain: keychain)
        var settings = AppSettings(); settings.provider = .custom; settings.mode = .visual
        settings.translationService = .api; settings.saveRecentResult = false
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "fixture"
        try store.save(settings, keys: [AIProvider.custom.rawValue: "fixture-key"])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        StubURLProtocol.registry.set { request in
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: Any]]
            XCTAssertTrue((messages[0]["content"] as! String).contains("QUICK MODE"))
            XCTAssertNotNil(messages[1]["content"] as? String)
            return (200, Data(#"{"choices":[{"message":{"content":"你好"}}]}"#.utf8))
        }
        let (result, _) = try await IntentTranslationWork.text("Hello", store: store,
            pipeline: TranslationPipeline(client: APIClient(session: session)), mode: .quick)
        XCTAssertEqual(result.translated, "你好"); XCTAssertEqual(result.mode, .quick)
        XCTAssertEqual(store.settings.mode, .visual); XCTAssertEqual(store.settings.translationService, .api)
    }

    func testSystemChoiceDoesNotRequireAPIKeyOrSendNetworkRequest() throws {
        #if targetEnvironment(simulator)
        let suite = "ScreenTranslate.SystemTest.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, keychain: KeychainStore(service: suite))
        var settings = AppSettings(); settings.mode = .quick; settings.quickEngine = .system
        try store.save(settings, keys: [:])
        let model = TranslationViewModel(store: store)
        model.text = "Hello"; model.translate()
        XCTAssertEqual(model.error, TranslationError.systemUnavailable.localizedDescription)
        XCTAssertFalse(model.busy); XCTAssertNil(model.systemRequest)
        #endif
    }

    func testVisualModeCannotTranslateTextWithoutImage() throws {
        let suite = "ScreenTranslate.VisualTest.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        var settings = AppSettings(); settings.mode = .visual
        try store.save(settings, keys: [:])
        let model = TranslationViewModel(store: store)
        model.text = "Hello"; model.translate()
        XCTAssertEqual(model.error, TranslationError.imageRequired.localizedDescription)
        XCTAssertFalse(model.busy)
    }
}
