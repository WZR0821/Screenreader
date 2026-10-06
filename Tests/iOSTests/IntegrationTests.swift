import XCTest
import UIKit
import AppIntents
import SwiftUI
@testable import ScreenTranslate

final class OCRIntegrationTests: XCTestCase {
    func testLongScreenshotRetainsSmallTextAndAvoidsTileDuplicates() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 10000)).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 720, height: 10000))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 28), .foregroundColor: UIColor.black]
            for index in 0..<28 {
                (String(format: "SCREEN ROW %02d", index) as NSString).draw(at: CGPoint(x: 40, y: 60 + index * 350), withAttributes: attributes)
            }
        }
        let result = try await OCRService().recognize(image, source: .english)
        for index in 0..<28 {
            let label = String(format: "SCREEN ROW %02d", index)
            XCTAssertTrue(result.text.contains(label), result.text)
            XCTAssertEqual(result.text.components(separatedBy: label).count - 1, 1, "Repeated across tiles: \(label)")
        }
    }
    func testExplicitSourceLanguagesConfigureRealOCR() async throws {
        for (language, text, expected) in [(SourceLanguage.chinese, "你好，这是中文测试。", "中文"),
                                          (.english, "Hello, this is English.", "Hello"),
                                          (.japanese, "こんにちは、世界。", "世界")] {
            let data = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 200)).pngData { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 200))
                (text as NSString).draw(at: CGPoint(x: 30, y: 60), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 44), .foregroundColor: UIColor.black])
            }
            let result = try await OCRService().recognize(data, source: language)
            XCTAssertTrue(result.text.contains(expected), "\(language.title): \(result.text)")
            XCTAssertEqual(result.languages, language.title)
        }
    }
    func testJapaneseAndEnglishOCRFromRealRenderedImage() async throws {
        let data = Self.fixtureImage()
        let result = try await OCRService().recognize(data)
        XCTAssertTrue(result.text.contains("Hello"), result.text)
        XCTAssertTrue(result.text.contains("世界"), result.text)
        XCTAssertTrue(result.text.contains("12345"), result.text)
        XCTAssertFalse(result.languages.isEmpty)
    }
    func testBlankImageShowsNoTextError() async {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).pngData { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        }
        do { _ = try await OCRService().recognize(data); XCTFail() }
        catch { XCTAssertEqual(error as? TranslationError, .noText) }
    }
    func testInvalidImageAndOversizedDataRejected() async {
        do { _ = try await OCRService().recognize(Data("invalid".utf8)); XCTFail() }
        catch { XCTAssertEqual(error as? TranslationError, .invalidImage) }
        do { _ = try await OCRService().recognize(Data(count: 25 * 1024 * 1024 + 1)); XCTFail() }
        catch { XCTAssertEqual(error as? TranslationError, .imageTooLarge) }
    }
    func testMixedLanguageDetection() {
        let result = LanguageDetector.describe("こんにちは。今日は良い天気ですね。\n\nThis is an English paragraph about the weather.")
        XCTAssertTrue(result.contains("日语"), result)
        XCTAssertTrue(result.contains("英语"), result)
    }
    func testCompleteImageToAPIToTranslationPipeline() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        StubURLProtocol.registry.set { request in
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            XCTAssertTrue(messages[1]["content"]!.contains("Hello"))
            XCTAssertTrue(messages[1]["content"]!.contains("世界"))
            return (200, Data(#"{"choices":[{"message":{"content":"你好，世界。订单号 12345。"}}]}"#.utf8))
        }
        var settings = AppSettings()
        settings.provider = .custom
        settings.configuration.baseURL = "https://mock.test/v1"
        settings.configuration.model = "fixture-model"
        let pipeline = TranslationPipeline(client: APIClient(session: session))
        let result = try await pipeline.image(Self.fixtureImage(), settings: settings, key: "fixture-key")
        XCTAssertEqual(result.translated, "你好，世界。订单号 12345。")
        XCTAssertTrue(result.original.contains("12345"))
        XCTAssertGreaterThan(result.elapsed, 0)
    }
    static func fixtureImage() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 900, height: 400)).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 400))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 44), .foregroundColor: UIColor.black]
            ("Hello, world!" as NSString).draw(at: CGPoint(x: 50, y: 50), withAttributes: attributes)
            ("こんにちは、世界。" as NSString).draw(at: CGPoint(x: 50, y: 150), withAttributes: attributes)
            ("Order 12345" as NSString).draw(at: CGPoint(x: 50, y: 260), withAttributes: attributes)
        }
    }
}

@MainActor
final class PersistenceIntegrationTests: XCTestCase {
    func testEditingSourceInvalidatesOldTranslationAndError() async throws {
        let suite = "ScreenTranslate.EditedSource.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainStore(service: suite)
        defer { defaults.removePersistentDomain(forName: suite); try? keychain.write("", provider: .custom) }
        let store = SettingsStore(defaults: defaults, keychain: keychain)
        var settings = AppSettings(); settings.provider = .custom; settings.saveRecentResult = false
        settings.configuration.baseURL = "https://mock.test/v1"; settings.configuration.model = "fixture"
        try store.save(settings, keys: [AIProvider.custom.rawValue: "fixture-key"])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        StubURLProtocol.registry.set { _ in (200, Data(#"{"choices":[{"message":{"content":"你好"}}]}"#.utf8)) }
        let model = TranslationViewModel(store: store, pipeline: TranslationPipeline(client: APIClient(session: session)))
        model.text = "Hello"; model.translate()
        for _ in 0..<40 where model.busy { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(model.result?.translated, "你好")
        model.text = "Goodbye"
        XCTAssertNil(model.result)
        model.error = "401"; model.text += "!"
        XCTAssertNil(model.error)
        model.translate()
        for _ in 0..<40 where model.busy { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertNotNil(model.result)
        model.invalidateTranslation()
        XCTAssertNil(model.result); XCTAssertEqual(model.text, "Goodbye!")
    }

    func testImageTranslationUpdatesEditorWithoutClearingNewResult() async throws {
        let suite = "ScreenTranslate.ImageEditor.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainStore(service: suite)
        defer { defaults.removePersistentDomain(forName: suite); try? keychain.write("", provider: .custom) }
        let store = SettingsStore(defaults: defaults, keychain: keychain)
        var settings = AppSettings(); settings.provider = .custom; settings.saveRecentResult = false
        settings.configuration.baseURL = "https://mock.test/v1"; settings.configuration.model = "fixture"
        try store.save(settings, keys: [AIProvider.custom.rawValue: "fixture-key"])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        StubURLProtocol.registry.set { _ in (200, Data(#"{"choices":[{"message":{"content":"你好，世界。"}}]}"#.utf8)) }
        let model = TranslationViewModel(store: store, pipeline: TranslationPipeline(client: APIClient(session: session)))
        try model.acceptImage(OCRIntegrationTests.fixtureImage())
        model.translate()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.text.contains("Hello"))
        XCTAssertEqual(model.result?.translated, "你好，世界。")
        XCTAssertNil(model.error)
        model.modeChanged()
        XCTAssertTrue(model.text.isEmpty, "Switching mode must re-recognize automatic OCR at the new quality")
        model.text = "Manually corrected text"
        model.modeChanged()
        XCTAssertEqual(model.text, "Manually corrected text", "Do not discard user corrections")
    }

    func testResultCardRendersSuccessLongTextAndError() throws {
        let result = TranslationResult(original: "Hello", translated: String(repeating: "这是一段较长的译文。", count: 100),
            sourceLanguages: "英语", target: "简体中文", engine: "测试接口", elapsed: 1)
        for (name, view) in [
            ("长译文结果卡片", TranslationSnippetView(result: result, error: nil, saved: true)),
            ("错误结果卡片", TranslationSnippetView(result: nil, error: "API Key 无效，请检查设置。", saved: false))] {
            let renderer = ImageRenderer(content: view.frame(width: 360).background(Color.white))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(image.size.height, 80)
            XCTAssertLessThan(image.size.height, 400, "Static snippets must stay within the system's compact presentation")
            let attachment = XCTAttachment(image: image)
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testAppIntentsDoNotOpenAppAndRequireAuthentication() {
        XCTAssertFalse(TranslateScreenshotIntent.openAppWhenRun)
        XCTAssertFalse(TranslateTextIntent.openAppWhenRun)
        XCTAssertEqual(TranslateScreenshotIntent.authenticationPolicy, .requiresAuthentication)
        XCTAssertEqual(TranslateTextIntent.authenticationPolicy, .requiresAuthentication)
    }

    func testIntentWorkerReturnsFullTranslationAndSavesSameResult() async throws {
        let suite = "ScreenTranslate.IntentTest.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let keychain = KeychainStore(service: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
            try? keychain.write("", provider: .custom)
            StubURLProtocol.registry.set(nil)
        }
        let store = SettingsStore(defaults: defaults, directory: directory, keychain: keychain)
        var settings = AppSettings(); settings.provider = .custom
        settings.configuration.baseURL = "https://mock.test/v1"; settings.configuration.model = "fixture"
        settings.source = .japanese; settings.target = .english
        try store.save(settings, keys: [AIProvider.custom.rawValue: "fixture-key"])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let fullTranslation = String(repeating: "完整译文。", count: 500)
        StubURLProtocol.registry.set { request in
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let prompt = (body["messages"] as! [[String: String]])[0]["content"]!
            XCTAssertTrue(prompt.contains("The source language is Japanese"))
            XCTAssertTrue(prompt.contains("Translate every part into English"))
            return (200, try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": fullTranslation]]]]))
        }
        let pipeline = TranslationPipeline(client: APIClient(session: session))
        let (result, saved) = try await IntentTranslationWork.image(OCRIntegrationTests.fixtureImage(), store: store, pipeline: pipeline)
        XCTAssertEqual(result.translated, fullTranslation)
        XCTAssertEqual(result.sourceLanguages, "日语")
        XCTAssertEqual(result.target, "英语")
        XCTAssertEqual(store.recentResult?.translated, fullTranslation)
        XCTAssertTrue(saved)
    }

    func testKeysRemainIsolatedAndCanBeUpdatedAndRemoved() throws {
        let keychain = KeychainStore(service: "ScreenTranslate.Tests.\(UUID())")
        defer { for provider in AIProvider.allCases { try? keychain.write("", provider: provider) } }
        try keychain.write("first-key", provider: .openAI)
        try keychain.write("second-key", provider: .deepSeek)
        try keychain.write("updated-key", provider: .openAI)
        XCTAssertEqual(try keychain.read(provider: .openAI), "updated-key")
        XCTAssertEqual(try keychain.read(provider: .deepSeek), "second-key")
        try keychain.write("", provider: .openAI)
        XCTAssertEqual(try keychain.read(provider: .openAI), "")
    }
    func testLanguageUpdatesPersistWithoutReplacingAPIKeyOrConfiguration() throws {
        let suite = "ScreenTranslate.LanguageTest.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainStore(service: suite)
        defer { defaults.removePersistentDomain(forName: suite); try? keychain.write("", provider: .custom) }
        let store = SettingsStore(defaults: defaults, keychain: keychain)
        var settings = AppSettings(); settings.provider = .custom
        settings.configuration.baseURL = "https://mock.test/v1"; settings.configuration.model = "saved-model"
        try store.save(settings, keys: [AIProvider.custom.rawValue: "unchanged-key"])
        try store.updateLanguages(source: .english, target: .japanese)
        let reloaded = SettingsStore(defaults: defaults, keychain: keychain)
        XCTAssertEqual(reloaded.settings.source, .english)
        XCTAssertEqual(reloaded.settings.target, .japanese)
        XCTAssertEqual(reloaded.settings.configuration, settings.configuration)
        XCTAssertEqual(try reloaded.credentials().1, "unchanged-key")
        try reloaded.swapLanguages()
        XCTAssertEqual(reloaded.settings.source, .japanese)
        XCTAssertEqual(reloaded.settings.target, .english)
    }
    func testSettingsAndRecentResultPersistAndPrivacyToggleDeletesFile() throws {
        let suite = "ScreenTranslate.Tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let keychain = KeychainStore(service: suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory); try? keychain.write("", provider: .openAI) }
        let store = SettingsStore(defaults: defaults, directory: directory, keychain: keychain)
        var settings = AppSettings(); settings.provider = .openAI; settings.configuration.model = "test-model"
        try store.save(settings, keys: [AIProvider.openAI.rawValue: "test-key"])
        let result = TranslationResult(original: "Hello", translated: "你好", sourceLanguages: "英语", target: "简体中文", engine: "fixture", elapsed: 1)
        try store.record(result)
        let reloaded = SettingsStore(defaults: defaults, directory: directory, keychain: keychain)
        XCTAssertEqual(reloaded.recentResult, result)
        XCTAssertEqual(try reloaded.credentials().1, "test-key")
        settings.saveRecentResult = false
        try reloaded.save(settings, keys: [:])
        XCTAssertNil(reloaded.recentResult)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("recent-result.json").path))
        try reloaded.record(result)
        XCTAssertNil(reloaded.recentResult)
    }
    func testCancellingUIWorkDoesNotRestoreOldResult() async throws {
        let suite = "ScreenTranslate.CancelTest.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainStore(service: suite)
        defer { defaults.removePersistentDomain(forName: suite); try? keychain.write("", provider: .custom) }
        let store = SettingsStore(defaults: defaults, keychain: keychain)
        var settings = AppSettings(); settings.provider = .custom
        settings.configuration.baseURL = "https://mock.test/v1"; settings.configuration.model = "fixture"
        try store.save(settings, keys: [AIProvider.custom.rawValue: "fixture-key"])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        StubURLProtocol.registry.set { _ in (200, Data(#"{"choices":[{"message":{"content":"旧结果"}}]}"#.utf8)) }
        let model = TranslationViewModel(store: store, pipeline: TranslationPipeline(client: APIClient(session: session)))
        model.text = "Hello"
        model.translate()
        model.clear()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(model.result)
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(model.phase, .idle)
    }
}
