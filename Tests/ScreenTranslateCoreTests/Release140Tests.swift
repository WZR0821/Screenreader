import XCTest
#if canImport(ScreenTranslateCore)
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

/// 1.4.0: provider error messages, streaming, chunking, reasoning, zh/ja checks.
final class ProviderErrorMessageTests: XCTestCase {
    func testStructuredMessageIsShownAndCredentialsAreMasked() {
        let body = Data(#"{"error":{"message":"Incorrect API key provided: sk-live-abcdef123456. Key test-key-secret-99 rejected.","type":"invalid_request_error"}}"#.utf8)
        let error = ProviderErrorMessage.error(status: 401, body: body, secrets: ["test-key-secret-99"])
        guard case .httpDetail(401, let detail) = error else { return XCTFail("Expected detail, got \(error)") }
        XCTAssertTrue(detail.hasPrefix("Incorrect API key provided"))
        XCTAssertFalse(detail.contains("abcdef123456"))
        XCTAssertFalse(detail.contains("test-key-secret-99"))
        let description = error.localizedDescription
        XCTAssertTrue(description.contains("HTTP 401"))
        XCTAssertTrue(description.contains("服务商原话：Incorrect API key provided"))
    }

    func testOtherProviderShapesAndLimits() {
        XCTAssertEqual(ProviderErrorMessage.extract(Data(#"[{"error":{"code":400,"message":"model not found"}}]"#.utf8)), "model not found")
        XCTAssertEqual(ProviderErrorMessage.extract(Data(#"{"detail":"Rate limit\nexceeded"}"#.utf8)), "Rate limit exceeded")
        XCTAssertEqual(ProviderErrorMessage.extract(Data(#"{"error":"quota exhausted"}"#.utf8)), "quota exhausted")
        XCTAssertEqual(ProviderErrorMessage.extract(Data(#"{"code":"x","api_key":"value-1234567"}"#.utf8)), nil)
        XCTAssertEqual(ProviderErrorMessage.sanitized(#"bad token: abcdefghijkl"#), "bad token: ••••")
        XCTAssertNil(ProviderErrorMessage.extract(Data("<html>502 Bad Gateway</html>".utf8)))
        let long = ProviderErrorMessage.sanitized(String(repeating: "上下文过长。", count: 80))!
        XCTAssertEqual(long.count, ProviderErrorMessage.maximumLength + 1)
        XCTAssertTrue(long.hasSuffix("…"))
    }

    func testHTTPErrorWithJSONBodyCarriesProviderMessage() async {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        StubURLProtocol.registry.set { _ in
            (400, Data(#"{"error":{"message":"This model's maximum context length is 8192 tokens."}}"#.utf8))
        }
        do {
            _ = try await APIClient(session: session).translate("Hello", settings: Release140Fixtures.settings(), apiKey: "fixture-key")
            XCTFail("Expected HTTP error")
        } catch {
            XCTAssertEqual(error as? TranslationError, .httpDetail(400, "This model's maximum context length is 8192 tokens."))
        }
    }
}

final class StreamingTests: XCTestCase {
    func testAnthropicEventsCollectTextAndDetectTruncation() throws {
        var stream = TranslationStreamAccumulator(style: .anthropicMessages)
        XCTAssertFalse(try stream.consume(line: "event: message_start"))
        XCTAssertFalse(try stream.consume(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"hmm"}}"#))
        XCTAssertTrue(try stream.consume(line: #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"你好"}}"#))
        XCTAssertTrue(try stream.consume(line: #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"，世界"}}\#r"#))
        XCTAssertEqual(stream.text, "你好，世界")
        XCTAssertEqual(try stream.finish().text, "你好，世界")
        _ = try stream.consume(line: #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#)
        XCTAssertThrowsError(try stream.finish()) { XCTAssertEqual($0 as? TranslationError, .incompleteTranslation) }
    }

    func testChatAndResponsesEventsAndStreamErrors() throws {
        var chat = TranslationStreamAccumulator(style: .chatCompletions)
        _ = try chat.consume(line: #"data: {"choices":[{"delta":{"reasoning_content":"thinking..."}}]}"#)
        _ = try chat.consume(line: #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#)
        _ = try chat.consume(line: #"data: {"choices":[],"usage":{"total_tokens":3}}"#)
        _ = try chat.consume(line: "data: [DONE]")
        XCTAssertEqual(try chat.finish().text, "Hello")
        _ = try chat.consume(line: #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#)
        XCTAssertThrowsError(try chat.finish()) { XCTAssertEqual($0 as? TranslationError, .incompleteTranslation) }

        var responses = TranslationStreamAccumulator(style: .responses)
        _ = try responses.consume(line: #"data: {"type":"response.output_text.delta","delta":"你好"}"#)
        XCTAssertEqual(try responses.finish().text, "你好")
        XCTAssertThrowsError(try responses.consume(line: #"data: {"type":"response.failed","response":{"error":{"message":"server overloaded"}}}"#)) {
            XCTAssertEqual($0 as? TranslationError, .streamFailure("server overloaded"))
        }
        var anthropic = TranslationStreamAccumulator(style: .anthropicMessages)
        XCTAssertThrowsError(try anthropic.consume(line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)) {
            XCTAssertEqual($0 as? TranslationError, .streamFailure("Overloaded"))
        }
        XCTAssertThrowsError(try TranslationStreamAccumulator(style: .chatCompletions).finish()) {
            XCTAssertEqual($0 as? TranslationError, .emptyResponse)
        }
    }

    func testLayoutPreviewNeverShowsRawJSON() {
        XCTAssertEqual(StreamingPreview.blocksText(""), "")
        XCTAssertEqual(StreamingPreview.blocksText(#"{"blocks":[{"id":1,"te"#), "")
        XCTAssertEqual(StreamingPreview.blocksText(#"{"blocks":[{"id":1,"text":"第一行\n第二行"},{"id":2,"text":"引号\"和你"#), "第一行\n第二行\n\n引号\"和你")
        // An escape cut off at the end of the received data is not shown half-decoded.
        XCTAssertEqual(StreamingPreview.blocksText(#"{"blocks":[{"id":1,"text":"价格\u00"#), "价格")
        XCTAssertEqual(StreamingPreview.blocksText(#"{"blocks":[{"id":1,"text":"表情😀"}]}"#), "表情😀")
    }

    func testPartialCollectorJoinsChunksInOrder() {
        let box = Release140Fixtures.Box()
        let collector = PartialTextCollector(count: 3, separators: ["\n\n", " "]) { box.set($0) }
        collector.update(2, "C")
        XCTAssertEqual(box.value, "C")
        collector.update(0, "A")
        XCTAssertEqual(box.value, "A\n\nC")
        collector.update(1, "B")
        XCTAssertEqual(box.value, "A\n\nB C")
    }

    func testStreamedReplyIsShownAsItArrivesAndValidatedAtTheEnd() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        StubURLProtocol.registry.set { request in
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            XCTAssertEqual(body["stream"] as? Bool, true)
            return (200, Data("""
            : keep-alive

            data: {"choices":[{"delta":{"role":"assistant"}}]}

            data: {"choices":[{"delta":{"content":"你好"}}]}

            data: {"choices":[{"delta":{"content":"，世界"},"finish_reason":"stop"}]}

            data: [DONE]

            """.utf8))
        }
        let box = Release140Fixtures.Box()
        let result = try await APIClient(session: session).translate("Hello, world", settings: Release140Fixtures.settings(),
                                                                    apiKey: "fixture-key", onPartial: { box.set($0) })
        XCTAssertEqual(result.text, "你好，世界")
        XCTAssertFalse(box.value.isEmpty)
        XCTAssertTrue("你好，世界".hasPrefix(box.value))
    }

    func testStreamingFallsBackWhenEndpointIgnoresStreamFlag() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        StubURLProtocol.registry.set { _ in
            (200, Data("{\n  \"choices\": [{\"message\": {\"content\": \"你好\"}, \"finish_reason\": \"stop\"}]\n}".utf8))
        }
        let result = try await APIClient(session: session).translate("Hello", settings: Release140Fixtures.settings(),
                                                                    apiKey: "fixture-key", onPartial: { _ in })
        XCTAssertEqual(result.text, "你好")
    }

    func testStreamingHTTPErrorAndLayoutStream() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        StubURLProtocol.registry.set { _ in (404, Data(#"{"error":{"message":"model gone-model does not exist"}}"#.utf8)) }
        do {
            _ = try await APIClient(session: session).translate("Hello", settings: Release140Fixtures.settings(),
                                                               apiKey: "fixture-key", onPartial: { _ in })
            XCTFail("Expected HTTP error")
        } catch { XCTAssertEqual(error as? TranslationError, .httpDetail(404, "model gone-model does not exist")) }

        StubURLProtocol.registry.set { _ in
            let pieces = [#"{\"blocks\":[{\"id\":1,"#, #"\"text\":\"标题\"},{\"id\":2,\"text\":\"最后"#, #"一段\"}]}"#]
            let lines = pieces.map { #"data: {"choices":[{"delta":{"content":""# + $0 + #""}}]}"# }
            return (200, Data((lines + ["data: [DONE]", ""]).joined(separator: "\n\n").utf8))
        }
        var settings = Release140Fixtures.settings(); settings.mode = .professional
        let box = Release140Fixtures.Box()
        let result = try await APIClient(session: session).translate("Title\n\nLast paragraph", settings: settings, apiKey: "fixture-key",
                                                                    timeout: 90, preserveBlocks: true, onPartial: { box.set($0) })
        XCTAssertEqual(result.blocks?.map(\.text), ["标题", "最后一段"])
        XCTAssertFalse(box.value.contains("{"))
    }
}

final class ChunkingTests: XCTestCase {
    func testShortTextIsNeverSplit() {
        XCTAssertEqual(TranslationChunking.textPlan("Hello\n\nWorld").pieces, ["Hello\n\nWorld"])
    }

    func testParagraphPlanRejoinsToTheSource() {
        let paragraphs = (1...6).map { String(repeating: "Paragraph \($0) text. ", count: 60) }
        let text = paragraphs.joined(separator: "\n\n")
        let plan = TranslationChunking.textPlan(text)
        XCTAssertGreaterThan(plan.pieces.count, 1)
        XCTAssertEqual(plan.separators.count, plan.pieces.count - 1)
        XCTAssertTrue(plan.pieces.allSatisfy { $0.count <= TranslationChunking.targetSize })
        XCTAssertEqual(Release140Fixtures.join(plan), text)
    }

    func testOneHugeLineSplitsAtSentencesAndKeepsSpacing() {
        let english = (1...400).map { "Sentence \($0) ends here." }.joined(separator: " ")
        let plan = TranslationChunking.textPlan(english)
        XCTAssertGreaterThan(plan.pieces.count, 1)
        XCTAssertTrue(plan.pieces.allSatisfy { $0.hasSuffix(".") && !$0.hasPrefix(" ") })
        XCTAssertEqual(Release140Fixtures.join(plan), english)
        let chinese = String(repeating: "这是一个很长的句子，没有换行。", count: 500)
        let chinesePlan = TranslationChunking.textPlan(chinese)
        XCTAssertGreaterThan(chinesePlan.pieces.count, 1)
        XCTAssertEqual(Release140Fixtures.join(chinesePlan), chinese)
        XCTAssertTrue(chinesePlan.pieces.allSatisfy { $0.count <= TranslationChunking.targetSize })
    }

    func testBlockGroupsKeepOrderAndNeverSplitABlock() {
        let blocks = (1...7).map { ReadingBlock(id: $0, text: String(repeating: "字", count: $0 == 4 ? 5_000 : 1_000)) }
        let groups = TranslationChunking.blockGroups(blocks)
        XCTAssertEqual(groups.flatMap { $0 }.map(\.id), Array(1...7))
        XCTAssertTrue(groups.contains { $0.map(\.id) == [4] })
        XCTAssertEqual(groups.first?.map(\.id), [1, 2])
    }

    func testRunKeepsOrderAndBoundsConcurrency() async throws {
        let tracker = Release140Fixtures.ConcurrencyTracker()
        let values = try await TranslationChunking.run(count: 8) { index in
            tracker.enter()
            try await Task.sleep(nanoseconds: UInt64((8 - index) * 5_000_000))
            tracker.leave()
            return index * 10
        }
        XCTAssertEqual(values, (0..<8).map { $0 * 10 })
        XCTAssertLessThanOrEqual(tracker.peak, TranslationChunking.maximumConcurrentRequests)
        XCTAssertGreaterThan(tracker.peak, 1)
    }

    func testLongPlainTextUsesSeveralRequestsAndRejoinsInOrder() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        let counter = RequestCounter()
        StubURLProtocol.registry.set { request in
            counter.increment()
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let input = (body["messages"] as! [[String: Any]])[1]["content"] as! String
            XCTAssertLessThanOrEqual(input.count, TranslationChunking.targetSize)
            // Echo the paragraph numbers so the merged order can be checked.
            let numbers = input.components(separatedBy: "\n\n").map { $0.split(separator: " ")[1] }
            let reply = numbers.map { "第\($0)段" }.joined(separator: "\n\n")
            return (200, try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": reply], "finish_reason": "stop"]]]))
        }
        let text = (1...6).map { String(repeating: "Paragraph \($0) text. ", count: 60) }.joined(separator: "\n\n")
        let result = try await APIClient(session: session).translate(text, settings: Release140Fixtures.settings(), apiKey: "fixture-key")
        XCTAssertGreaterThan(counter.value, 1)
        XCTAssertEqual(result.text, (1...6).map { "第\($0)段" }.joined(separator: "\n\n"))
    }

    func testLongProfessionalLayoutIsSplitByBlocksAndRenumbered() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        let counter = RequestCounter()
        StubURLProtocol.registry.set { request in
            counter.increment()
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let input = (body["messages"] as! [[String: Any]])[1]["content"] as! String
            let document = try JSONDecoder().decode(ProfessionalLayout.Document.self, from: Data(input.utf8))
            XCTAssertEqual(document.blocks.first?.id, 1)
            let reply = ProfessionalLayout.Document(blocks: document.blocks.map {
                .init(id: $0.id, text: "译文" + $0.text.prefix(while: { $0 != " " }))
            })
            let content = String(decoding: try JSONEncoder().encode(reply), as: UTF8.self)
            return (200, try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content], "finish_reason": "stop"]]]))
        }
        let blocks = (1...5).map { ReadingBlock(id: $0, text: "B\($0) " + String(repeating: "word ", count: 300)) }
        var settings = Release140Fixtures.settings(); settings.mode = .professional
        let source = blocks.map(\.text).joined(separator: "\n\n")
        let result = try await APIClient(session: session).translate(source, settings: settings, apiKey: "fixture-key",
                                                                    timeout: 90, preserveBlocks: true, readingBlocks: blocks)
        XCTAssertGreaterThan(counter.value, 1)
        XCTAssertEqual(result.blocks?.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertEqual(result.blocks?.map(\.text), (1...5).map { "译文B\($0)" })
        XCTAssertEqual(result.blocks?.map(\.original), blocks.map(\.text))
        XCTAssertEqual(result.text, (1...5).map { "译文B\($0)" }.joined(separator: "\n\n"))
    }
}

final class OutputLanguageTests: XCTestCase {
    func testJapaneseTargetRejectsAChineseReply() {
        let chinese = String(repeating: "这个时候我们还要说明，对于东京车站的门口问题，现在没有发现长时间的关闭。", count: 3)
        XCTAssertThrowsError(try APIClient.validateOutputLanguage(chinese, target: .japanese)) {
            XCTAssertEqual($0 as? TranslationError, .unexpectedLanguage)
        }
        let japanese = String(repeating: "東京駅の入口は、現在長時間閉鎖されていません。詳しくは係員にお問い合わせください。", count: 3)
        XCTAssertNoThrow(try APIClient.validateOutputLanguage(japanese, target: .japanese))
        XCTAssertNoThrow(try APIClient.validateOutputLanguage("东京国立博物馆", target: .japanese))
        XCTAssertNoThrow(try APIClient.validateOutputLanguage(chinese, target: .japanese, fromImage: true))
    }

    func testChineseTargetRejectsAJapaneseReply() {
        let japanese = String(repeating: "このページでは、会員校の学生と教職員が無料で博物館を見学できることを説明しています。", count: 3)
        XCTAssertThrowsError(try APIClient.validateOutputLanguage(japanese, target: .simplifiedChinese)) {
            XCTAssertEqual($0 as? TranslationError, .unexpectedLanguage)
        }
        let chinese = String(repeating: "本页说明会员学校的学生和教职员工可以免费参观博物馆，详情请咨询工作人员。", count: 3)
            + "相关作品：「ドラゴンクエスト」、「ファイナルファンタジー」。"
        XCTAssertNoThrow(try APIClient.validateOutputLanguage(chinese, target: .simplifiedChinese))
        XCTAssertNoThrow(try APIClient.validateOutputLanguage(japanese, target: .simplifiedChinese, fromImage: true))
    }
}

final class ReasoningTests: XCTestCase {
    private func body(_ provider: AIProvider, model: String, style: APIStyle? = nil,
                      reasoning: ReasoningEffort?, mode: TranslationMode = .quick) -> [String: Any] {
        var settings = AppSettings()
        settings.provider = provider
        settings.mode = mode
        settings.configuration.model = model
        if let style { settings.configuration.style = style }
        settings.configuration.reasoning = reasoning
        var body: [String: Any] = ["model": model]
        if settings.configuration.style == .anthropicMessages { body["max_tokens"] = 8192 }
        APIClient.applyReasoning(to: &body, settings: settings, configuration: settings.configuration, model: model)
        return body
    }

    func testAutomaticKeepsPreviousBehaviour() {
        let deepSeek = body(.deepSeek, model: "deepseek-flash", style: .chatCompletions, reasoning: nil, mode: .quick)
        XCTAssertEqual(deepSeek["thinking"] as? [String: String], ["type": "disabled"])
        XCTAssertNil(deepSeek["reasoning_effort"])
        let professional = body(.deepSeek, model: "deepseek-flash", style: .chatCompletions, reasoning: nil, mode: .professional)
        XCTAssertEqual(professional["reasoning_effort"] as? String, "low")
        XCTAssertEqual(body(.openAI, model: "gpt-6-luna", style: .responses, reasoning: nil)["reasoning"] as? [String: String], ["effort": "none"])
        // Quick mode lowers Claude's effort since 1.3.3 (see Release133Tests).
        let claude = body(.claude, model: "claude-sonnet-5-5", reasoning: nil, mode: .professional)
        XCTAssertEqual(claude.count, 2)
        XCTAssertEqual(claude["max_tokens"] as? Int, 8192)
        XCTAssertEqual(body(.custom, model: "x", style: .chatCompletions, reasoning: nil).count, 1)
    }

    func testExplicitEffortUsesEachProvidersFormat() {
        XCTAssertEqual(body(.openAI, model: "gpt-6.1-sol", style: .responses, reasoning: .high)["reasoning"] as? [String: String], ["effort": "high"])
        XCTAssertEqual(body(.openAI, model: "gpt-6.1-sol", style: .chatCompletions, reasoning: .off)["reasoning_effort"] as? String, "none")
        let deepSeekOff = body(.deepSeek, model: "deepseek-new", style: .chatCompletions, reasoning: .off, mode: .professional)
        XCTAssertEqual(deepSeekOff["thinking"] as? [String: String], ["type": "disabled"])
        XCTAssertNil(deepSeekOff["reasoning_effort"])
        let deepSeekHigh = body(.deepSeek, model: "deepseek-new", style: .anthropicMessages, reasoning: .high)
        XCTAssertEqual(deepSeekHigh["thinking"] as? [String: String], ["type": "enabled"])
        XCTAssertEqual(deepSeekHigh["output_config"] as? [String: String], ["effort": "high"])
        XCTAssertEqual(body(.gemini, model: "gemini-3.8-flash", style: .chatCompletions, reasoning: .off)["reasoning_effort"] as? String, "minimal")
        XCTAssertEqual(body(.gemini, model: "gemini-2.5-flash", style: .chatCompletions, reasoning: .off)["reasoning_effort"] as? String, "none")
        XCTAssertEqual(body(.qwen, model: "qwen-plus", style: .chatCompletions, reasoning: .off)["enable_thinking"] as? Bool, false)
        // A choice the provider does not offer falls back to 自动.
        XCTAssertNil(body(.qwen, model: "qwen-plus", style: .chatCompletions, reasoning: .high)["enable_thinking"])
    }

    func testClaudeThinkingMatchesEachModelGeneration() {
        let haiku = body(.claude, model: "claude-haiku-4-5", reasoning: .medium)
        XCTAssertEqual((haiku["thinking"] as? [String: Any])?["budget_tokens"] as? Int, 4_096)
        XCTAssertEqual(haiku["max_tokens"] as? Int, 8_192 + 4_096)
        XCTAssertNil(haiku["output_config"])
        XCTAssertEqual(body(.claude, model: "claude-haiku-4-5", reasoning: .off).count, 2)
        let sonnetHigh = body(.claude, model: "claude-sonnet-5-5", reasoning: .high)
        XCTAssertEqual(sonnetHigh["thinking"] as? [String: String], ["type": "adaptive"])
        XCTAssertEqual(sonnetHigh["output_config"] as? [String: String], ["effort": "high"])
        XCTAssertEqual(sonnetHigh["max_tokens"] as? Int, 16_000)
        XCTAssertEqual(body(.claude, model: "claude-sonnet-5-5", reasoning: .off)["thinking"] as? [String: String], ["type": "between_tools"])
        let opusOff = body(.claude, model: "claude-opus-5-5", reasoning: .off)
        XCTAssertNil(opusOff["thinking"])
        XCTAssertEqual(opusOff["output_config"] as? [String: String], ["effort": "low"])
        XCTAssertEqual(body(.claude, model: "claude-opus-4-8", reasoning: .off)["thinking"] as? [String: String], ["type": "disabled"])
    }

    func testReasoningSettingIsSavedPerProviderAndOldDataStillLoads() throws {
        let old = Data(#"{"baseURL":"https://api.deepseek.com","model":"deepseek-flash","style":"chatCompletions"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ProviderConfiguration.self, from: old).reasoning)
        let unknown = Data(#"{"baseURL":"https://x.test","model":"m","style":"responses","reasoning":"extreme"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ProviderConfiguration.self, from: unknown).reasoning)
        var settings = AppSettings()
        settings.provider = .claude
        settings.configuration.reasoning = .high
        settings.provider = .openAI
        settings.configuration.reasoning = .off
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.configurations[AIProvider.claude.rawValue]?.reasoning, .high)
        XCTAssertEqual(restored.configuration.reasoning, .off)
        // 自动 adds nothing to the saved form, so cache keys from 1.3.0 stay valid.
        let encoded = String(decoding: try JSONEncoder().encode(ProviderConfiguration(provider: .deepSeek)), as: UTF8.self)
        XCTAssertFalse(encoded.contains("reasoning"))
    }
}

enum Release140Fixtures {
    static func settings() -> AppSettings {
        var value = AppSettings()
        value.provider = .custom
        value.configuration.baseURL = "https://mock.test/v1"
        value.configuration.model = "test-model"
        value.configuration.style = .chatCompletions
        return value
    }

    static func join(_ plan: TranslationChunking.TextPlan) -> String {
        var text = plan.pieces[0]
        for index in plan.pieces.indices.dropFirst() { text += plan.separators[index - 1] + plan.pieces[index] }
        return text
    }

    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = ""
        func set(_ value: String) { lock.lock(); stored = value; lock.unlock() }
        var value: String { lock.lock(); defer { lock.unlock() }; return stored }
    }

    final class ConcurrencyTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var current = 0
        private(set) var peak = 0
        func enter() { lock.lock(); current += 1; peak = max(peak, current); lock.unlock() }
        func leave() { lock.lock(); current -= 1; lock.unlock() }
    }
}
