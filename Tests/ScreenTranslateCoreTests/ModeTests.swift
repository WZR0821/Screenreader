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

final class ModeTests: XCTestCase {
    func testLegacyModeMigrationPreservesVisualAndSpeedPreference() throws {
        for (image, speed, expected) in [("visual", true, TranslationMode.visual), ("text", true, .quick), ("text", false, .professional)] {
            let data = Data("{\"imageMode\":\"\(image)\",\"preferSpeed\":\(speed)}".utf8)
            let saved = try JSONDecoder().decode(AppSettings.self, from: data)
            XCTAssertEqual(saved.mode, expected)
            XCTAssertEqual(saved.quickEngine, .api)
            XCTAssertFalse(saved.askModeInShortcuts)
        }
    }

    func testAPIModesRoundTripIndependently() throws {
        for mode in TranslationMode.allCases {
            var settings = AppSettings(); settings.mode = mode; settings.translationService = .api; settings.askModeInShortcuts = true
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)), settings)
            XCTAssertEqual(settings.preferSpeed, mode == .quick)
            XCTAssertEqual(settings.imageMode == .visual, mode == .visual)
        }
    }

    func testProfessionalRestoresOrderAndKeepsPriceAndListLines() throws {
        let input = ProfessionalLayout("Title\n\nPrice 1,200\nQuantity 1\n\nLast option")
        let translated = #"{"blocks":[{"id":3,"text":"最后选项"},{"id":1,"text":"标题"},{"id":2,"text":"价格 1,200\n数量 1"}]}"#
        XCTAssertEqual(try input.restore(translated), "标题\n\n价格 1,200\n数量 1\n\n最后选项")
    }

    func testProfessionalRejectsMissingDuplicateEmptyAndInventedBlocks() throws {
        let layout = ProfessionalLayout("One\n\nTwo")
        for bad in [#"{"blocks":[{"id":1,"text":"一"}]}"#,
                    #"{"blocks":[{"id":1,"text":"一"},{"id":1,"text":"二"}]}"#,
                    #"{"blocks":[{"id":1,"text":"一"},{"id":2,"text":" "}]}"#,
                    #"{"blocks":[{"id":1,"text":"一"},{"id":3,"text":"二"}]}"#,
                    "总结：只有一段。"] {
            XCTAssertThrowsError(try layout.restore(bad)) { XCTAssertEqual($0 as? TranslationError, .incompleteLayout) }
        }
    }

    func testQuickPromptIsShortAndVisualSeparatesTwoMeanings() throws {
        var settings = AppSettings(); settings.mode = .quick
        let quick = try TextPreparation.instructions(settings: settings)
        settings.mode = .professional
        XCTAssertLessThan(quick.count, try TextPreparation.instructions(settings: settings).count)
        let visual = try TextPreparation.imageInstructions(settings: settings)
        XCTAssertTrue(visual.contains("Text meaning")); XCTAssertTrue(visual.contains("Scene")); XCTAssertTrue(visual.contains("do not guess"))
    }

    func testProfessionalUsesOneRequestAndRestoresEveryProtocol() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        for style in APIStyle.allCases {
            var settings = AppSettings(); settings.provider = .custom; settings.mode = .professional
            settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "fixture"
            settings.configuration.style = style
            StubURLProtocol.registry.set { request in
                let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
                let input = style == .responses ? body["input"] as! String : (body["messages"] as! [[String: Any]]).last!["content"] as! String
                let doc = try JSONDecoder().decode(ProfessionalLayout.Document.self, from: Data(input.utf8))
                XCTAssertEqual(doc.blocks.map(\.id), [1, 2])
                XCTAssertEqual(doc.blocks.map(\.text), ["Title", "Last"])
                XCTAssertNil(body["thinking"]); XCTAssertNil(body["reasoning"])
                XCTAssertEqual(request.timeoutInterval, 90)
                let translated = #"{"blocks":[{"id":2,"text":"最后"},{"id":1,"text":"标题"}]}"#
                let response: [String: Any]
                switch style {
                case .chatCompletions: response = ["choices": [["message": ["content": translated]]]]
                case .responses: response = ["output": [["type": "message", "content": [["type": "output_text", "text": translated]]]]]
                case .anthropicMessages: response = ["content": [["type": "text", "text": translated]]]
                }
                return (200, try JSONSerialization.data(withJSONObject: response))
            }
            let result = try await APIClient(session: session).translate("Title\n\nLast", settings: settings, apiKey: "fixture-key", timeout: 90, preserveBlocks: true)
            XCTAssertEqual(result.text, "标题\n\n最后")
        }
    }
}
