import XCTest
@testable import ScreenTranslate

@MainActor
final class PreferencesIntegrationTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var directory: URL!
    private var keychain: KeychainStore!
    override func setUp() {
        suite = "ScreenTranslate.Preferences.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        keychain = KeychainStore(service: suite)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
        try? keychain.write("", provider: .custom)
    }
    private func store() -> SettingsStore { SettingsStore(defaults: defaults, directory: directory, keychain: keychain) }
    private func result(_ number: Int) -> TranslationResult {
        TranslationResult(original: "Original \(number)", translated: "译文 \(number)", sourceLanguages: "英语", target: "中文", engine: "fixture", elapsed: 0.1)
    }

    func testLegacyResultMigratesThenKeepsMultipleResultsAcrossStores() throws {
        let legacy = result(0)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(legacy).write(to: directory.appendingPathComponent("recent-result.json"))
        let first = store(); let second = store()
        XCTAssertEqual(first.history, [legacy])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("recent-result.json").path))
        let one = result(1), two = result(2)
        try first.record(one); try second.record(two)
        first.refreshRecent()
        XCTAssertEqual(first.history, [two, one, legacy])
        XCTAssertEqual(store().history, first.history)
    }

    func testRetentionDeduplicationDeletionAndDisableArePersistent() throws {
        let first = store()
        for number in 0..<35 { try first.record(result(number)) }
        XCTAssertEqual(first.history.count, 30)
        XCTAssertEqual(first.history.last?.original, "Original 5")
        let latest = try XCTUnwrap(first.recentResult)
        try first.record(latest)
        XCTAssertEqual(first.history.count, 30)
        var settings = first.settings; settings.historyLimit = 10
        try first.save(settings, keys: [:])
        XCTAssertEqual(store().history.count, 10)
        try first.deleteResult(latest.id)
        XCTAssertEqual(store().history.count, 9)
        XCTAssertFalse(store().history.contains { $0.id == latest.id })
        settings.saveRecentResult = false
        try first.save(settings, keys: [:])
        try first.record(result(99))
        XCTAssertTrue(store().history.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
    }

    func testCorruptHistoryIsNotSilentlyOverwritten() throws {
        let first = store(); try first.record(result(1))
        let file = directory.appendingPathComponent("history.json")
        let broken = Data("broken file".utf8); try broken.write(to: file)
        XCTAssertThrowsError(try first.record(result(2))) { XCTAssertEqual($0 as? TranslationError, .persistence) }
        XCTAssertEqual(first.history.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), broken)
        try first.clearRecent()
        XCTAssertTrue(first.history.isEmpty)
    }

    func testSwitchingServiceRestrictsModesWithoutLosingCredentialsOrColors() throws {
        let first = store()
        var settings = first.settings; settings.provider = .custom; settings.mode = .professional
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "fixture"
        settings.accentTheme = .rose; settings.reader.showOriginal = true; settings.askModeInShortcuts = true
        try first.save(settings, keys: [AIProvider.custom.rawValue: "fixture-key"])
        try first.updateQuickEngine(.system)
        XCTAssertEqual(first.settings.mode, .quick); XCTAssertFalse(first.settings.askModeInShortcuts)
        XCTAssertThrowsError(try first.updateMode(.professional)) { XCTAssertEqual($0 as? TranslationError, .modeUnavailable) }
        XCTAssertThrowsError(try first.credentials(for: .visual)) { XCTAssertEqual($0 as? TranslationError, .modeUnavailable) }
        let (snapshot, key) = try first.credentials(for: .quick)
        XCTAssertEqual(key, "fixture-key"); XCTAssertEqual(snapshot.translationService, .system)
        try first.updateQuickEngine(.api); try first.updateMode(.visual)
        let reloaded = store()
        XCTAssertEqual(reloaded.settings.mode, .visual); XCTAssertEqual(reloaded.settings.accentTheme, .rose)
        XCTAssertTrue(reloaded.settings.reader.showOriginal)
        XCTAssertEqual(reloaded.settings.configuration.model, "fixture")
    }

    func testFullDocumentUsesReaderAppearanceAndEscapesOriginal() {
        var settings = AppSettings(); settings.appearance = .dark
        settings.reader = .init(textSize: .large, spacing: .relaxed, showOriginal: true)
        var value = result(1); value.original = "<script>not executable</script>"; value.translated = "标题\n\n完整的最后一段"; value.mode = .professional
        value.blocks = [.init(id: 1, text: "标题", kind: .heading), .init(id: 2, text: "完整的最后一段", kind: .paragraph)]
        let html = String(decoding: TranslationDocument.html(value, settings: settings), as: UTF8.self)
        XCTAssertTrue(html.contains("font:20.0px/1.9"))
        XCTAssertTrue(html.contains("margin:0 0 24.0px"))
        XCTAssertTrue(html.contains("color-scheme:dark")); XCTAssertFalse(html.contains("prefers-color-scheme"))
        XCTAssertTrue(html.contains("<h1>标题</h1>")); XCTAssertTrue(html.contains("完整的最后一段"))
        XCTAssertTrue(html.contains("&lt;script&gt;not executable&lt;/script&gt;")); XCTAssertFalse(html.contains("<script>"))
        settings.reader.showOriginal = false
        let collapsed = String(decoding: TranslationDocument.html(value, settings: settings), as: UTF8.self)
        XCTAssertTrue(collapsed.contains("<details class=\"original\"><summary>查看原文</summary>"))
        XCTAssertTrue(collapsed.contains("not executable"), "Original must remain available on demand")
        XCTAssertFalse(collapsed.contains("class=\"original\" open"))
    }
}
