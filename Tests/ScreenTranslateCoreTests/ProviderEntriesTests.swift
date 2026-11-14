import XCTest
#if canImport(ScreenTranslateCore)
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

/// Provider entries: the 供应商 list, the models kept under each provider,
/// and what is written to and read from saved settings.
final class ProviderEntriesTests: XCTestCase {
    private func restored(_ settings: AppSettings) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    }
    private func savedForm(_ settings: AppSettings) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
    }

    func testSettingsSavedByEarlierVersionsLoadUnchanged() throws {
        let saved = Data(#"{"provider":"claude","configurations":{"claude":{"baseURL":"https://api.anthropic.com/v1","model":"claude-haiku-4-5","style":"anthropicMessages","reasoning":"low"},"openAI":{"baseURL":"https://api.openai.com/v1","model":"gpt-6-luna","style":"responses"}},"target":"简体中文"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: saved)
        XCTAssertEqual(settings.activeID, "claude")
        XCTAssertEqual(settings.provider, .claude)
        XCTAssertNil(settings.providerList)
        XCTAssertEqual(settings.configuration.model, "claude-haiku-4-5")
        XCTAssertEqual(settings.engineLabel, "Claude · claude-haiku-4-5")
        // The model an earlier version used stays first with its own settings;
        // the provider's presets follow.
        let models = settings.savedModels(for: "claude")
        XCTAssertEqual(models.first, SavedModel(id: "claude-haiku-4-5", style: .anthropicMessages, reasoning: .low))
        XCTAssertEqual(models.dropFirst().map(\.id), AIProvider.claude.models.map(\.id))
        // Only the provider in use and those with a key are listed, in the page's order.
        XCTAssertEqual(settings.listedProviderIDs(keyed: []), ["claude"])
        XCTAssertEqual(settings.listedProviderIDs(keyed: ["custom", "gemini", "openAI"]), ["claude", "openAI", "gemini", "custom"])
    }

    func testSavedFormStaysReadableByEarlierVersions() throws {
        var settings = AppSettings()
        settings.provider = .openAI
        var saved = try savedForm(settings)
        XCTAssertEqual(saved["provider"] as? String, "openAI")
        XCTAssertNil(saved["activeProvider"])
        XCTAssertNil(saved["providers"])

        // A provider earlier versions do not know is written as 自定义 for
        // them, with the real entry beside it.
        settings.provider = .doubao
        saved = try savedForm(settings)
        XCTAssertEqual(saved["provider"] as? String, "custom")
        XCTAssertEqual(saved["activeProvider"] as? String, "doubao")
        XCTAssertEqual(try restored(settings).activeID, "doubao")
        XCTAssertEqual(try restored(settings).provider, .doubao)

        settings.activeID = "custom-1"
        saved = try savedForm(settings)
        XCTAssertEqual(saved["provider"] as? String, "custom")
        XCTAssertEqual(saved["activeProvider"] as? String, "custom-1")
        XCTAssertEqual(try restored(settings).activeID, "custom-1")
        XCTAssertEqual(try restored(settings).provider, .custom)
    }

    func testAddingAndRemovingProviders() throws {
        var settings = AppSettings() // DeepSeek in use, nothing set up yet.
        var doubao = ProviderConfiguration(provider: .doubao)
        doubao.models = [SavedModel(id: "doubao-seed-2-1-lite-260915", style: .chatCompletions)]
        XCTAssertEqual(settings.addProvider(.doubao, configuration: doubao, keyed: []), "doubao")
        XCTAssertEqual(settings.providerList, ["deepSeek", "doubao"])
        XCTAssertEqual(settings.activeID, "deepSeek", "Adding a provider does not switch to it")
        XCTAssertEqual(settings.savedModels(for: "doubao").map(\.id), ["doubao-seed-2-1-lite-260915"])

        // The first custom service takes the built-in entry; later ones get their own id.
        var custom = ProviderConfiguration(provider: .custom)
        custom.baseURL = "https://one.example/v1"; custom.model = "m1"; custom.name = "One"
        XCTAssertEqual(settings.addProvider(.custom, configuration: custom, keyed: []) { "custom-2" }, "custom")
        custom.baseURL = "https://two.example/v1"; custom.name = "Two"
        XCTAssertEqual(settings.addProvider(.custom, configuration: custom, keyed: []) { "custom-2" }, "custom-2")
        XCTAssertEqual(settings.providerList, ["deepSeek", "doubao", "custom", "custom-2"])
        XCTAssertEqual(settings.displayName(for: "custom"), "One")
        XCTAssertEqual(settings.displayName(for: "custom-2"), "Two")
        XCTAssertEqual(settings.displayName(for: "doubao"), "豆包")
        XCTAssertEqual(AIProvider.kind(of: "custom-2"), .custom)

        settings.activate("custom-2")
        XCTAssertEqual(settings.provider, .custom)
        XCTAssertEqual(settings.configuration.baseURL, "https://two.example/v1")
        XCTAssertEqual(settings.engineLabel, "Two · m1")
        XCTAssertFalse(settings.removeProvider("custom-2", keyed: []), "The entry in use cannot be removed")
        XCTAssertTrue(settings.removeProvider("doubao", keyed: []))
        XCTAssertEqual(settings.providerList, ["deepSeek", "custom", "custom-2"])
        XCTAssertNil(settings.configurations["doubao"])

        let copy = try restored(settings)
        XCTAssertEqual(copy.providerList, settings.providerList)
        XCTAssertEqual(copy.configurations, settings.configurations)
        XCTAssertEqual(copy.activeID, "custom-2")
    }

    func testEachModelKeepsItsOwnFormatAndReasoning() throws {
        var settings = AppSettings()
        settings.provider = .openAI // gpt-6-luna over Responses.
        settings.updateConfiguration(for: "openAI") {
            $0.upsert(SavedModel(id: "gpt-6.1-sol", style: .chatCompletions, reasoning: .high), provider: .openAI)
        }
        XCTAssertEqual(settings.configuration.model, "gpt-6-luna", "Editing another model leaves the one in use alone")
        XCTAssertEqual(settings.configuration.style, .responses)
        XCTAssertEqual(settings.savedModels(for: "openAI").map(\.id), AIProvider.openAI.models.map(\.id))

        settings.activate("openAI", model: "gpt-6.1-sol")
        XCTAssertEqual(settings.configuration.model, "gpt-6.1-sol")
        XCTAssertEqual(settings.configuration.style, .chatCompletions)
        XCTAssertEqual(settings.configuration.reasoning, .high)
        XCTAssertTrue(settings.isInUse(model: "gpt-6.1-sol", of: "openAI"))
        XCTAssertFalse(settings.isInUse(model: "gpt-6-luna", of: "openAI"))
        XCTAssertFalse(settings.isInUse(model: "gpt-6.1-sol", of: "deepSeek"))

        // Going back restores the first model's own settings.
        settings.activate("openAI", model: "gpt-6-luna")
        XCTAssertEqual(settings.configuration.style, .responses)
        XCTAssertNil(settings.configuration.reasoning)
        XCTAssertEqual(try restored(settings).configurations, settings.configurations)

        // Removing the model in use hands over to the next kept one.
        settings.updateConfiguration(for: "openAI") { $0.removeModel("gpt-6-luna", provider: .openAI) }
        XCTAssertEqual(settings.savedModels(for: "openAI").map(\.id), ["gpt-6.1-sol", "gpt-4.1-mini"])
        XCTAssertEqual(settings.configuration.model, "gpt-6.1-sol")
        XCTAssertEqual(settings.configuration.style, .chatCompletions)
        settings.updateConfiguration(for: "openAI") {
            $0.removeModel("gpt-6.1-sol", provider: .openAI); $0.removeModel("gpt-4.1-mini", provider: .openAI)
        }
        XCTAssertEqual(settings.configuration.model, "")
        XCTAssertTrue(settings.savedModels(for: "openAI").isEmpty, "An emptied list does not fall back to the presets")
    }

    func testTypedModelIDsAreTrimmedAndNotDuplicated() {
        var configuration = ProviderConfiguration(provider: .custom)
        configuration.upsert(SavedModel(id: "  my-model \n", style: .chatCompletions), provider: .custom)
        XCTAssertEqual(configuration.model, "my-model", "The first model of an empty provider is put in use")
        configuration.upsert(SavedModel(id: "my-model", style: .anthropicMessages, reasoning: .low), provider: .custom)
        configuration.upsert(SavedModel(id: " ", style: .chatCompletions), provider: .custom)
        XCTAssertEqual(configuration.savedModels(for: .custom), [SavedModel(id: "my-model", style: .anthropicMessages, reasoning: .low)])
        XCTAssertEqual(configuration.style, .anthropicMessages)
        XCTAssertEqual(configuration.reasoning, .low)
        configuration.select("missing", provider: .custom)
        XCTAssertEqual(configuration.model, "my-model", "Selecting an unknown model changes nothing")
    }

    func testCacheKeyFollowsOnlyWhatARequestUses() throws {
        var settings = AppSettings()
        func key(_ value: AppSettings) throws -> String {
            try TranslationCache.key(text: "Hello", settings: value, apiKey: "k", readingBlocks: nil, fromImageText: false)
        }
        let original = try key(settings)
        // Keeping one more model, or naming the service, sends the same request.
        settings.updateConfiguration(for: settings.activeID) {
            $0.upsert(SavedModel(id: "extra-model", style: .chatCompletions), provider: .deepSeek)
            $0.name = "Mine"
        }
        XCTAssertEqual(try key(settings), original)
        settings.activate(settings.activeID, model: "extra-model")
        XCTAssertNotEqual(try key(settings), original)
    }

    func testPresetOrderLinksAndEndpoints() throws {
        XCTAssertEqual(Array(AIProvider.presets.prefix(3)), [.claude, .openAI, .deepSeek])
        XCTAssertEqual(Set(AIProvider.presets), Set(AIProvider.allCases).subtracting([.custom]))
        XCTAssertEqual(AIProvider.presets.count, AIProvider.allCases.count - 1, "No provider is listed twice")
        for provider in AIProvider.allCases {
            XCTAssertEqual(provider.documentationURL.scheme, "https")
            XCTAssertFalse(provider.title.isEmpty); XCTAssertFalse(provider.subtitle.isEmpty)
            XCTAssertFalse(provider.setupNote.isEmpty); XCTAssertFalse(provider.reasoningNote.isEmpty)
            if let url = provider.keyURL { XCTAssertEqual(url.scheme, "https") }
            XCTAssertEqual(AIProvider.kind(of: provider.rawValue), provider)
        }
        XCTAssertNil(AIProvider.custom.keyURL)
        XCTAssertEqual(AIProvider.kind(of: "custom-0a1b"), .custom)
        let endpoints: [AIProvider: String] = [
            .doubao: "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
            .kimi: "https://api.moonshot.cn/v1/chat/completions",
            .zhipu: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
            .minimax: "https://api.minimax.cn/v1/chat/completions"
        ]
        for (provider, endpoint) in endpoints {
            XCTAssertEqual(provider.defaultStyle, .chatCompletions)
            XCTAssertFalse(AIProvider.legacyCases.contains(provider))
            XCTAssertEqual(try APIClient.endpoint(configuration: ProviderConfiguration(provider: provider)).absoluteString, endpoint)
        }
    }
}

/// What 豆包, Kimi, 智谱 and MiniMax requests carry, from each provider's documentation.
final class NewProviderRequestTests: XCTestCase {
    private func body(_ provider: AIProvider, model: String, reasoning: ReasoningEffort? = nil,
                      mode: TranslationMode = .quick, style: APIStyle = .chatCompletions) -> [String: Any] {
        var settings = AppSettings()
        settings.provider = provider
        settings.mode = mode
        settings.configuration.model = model
        settings.configuration.style = style
        settings.configuration.reasoning = reasoning
        var body: [String: Any] = ["model": model]
        APIClient.applyOutputLimits(to: &body, settings: settings, configuration: settings.configuration, model: model)
        APIClient.applyReasoning(to: &body, settings: settings, configuration: settings.configuration, model: model)
        return body
    }
    private func thinking(_ body: [String: Any]) -> String? { (body["thinking"] as? [String: String])?["type"] }
    private func effort(_ body: [String: Any]) -> String? { body["reasoning_effort"] as? String }

    func testDoubao() {
        let model = "doubao-seed-2-1-lite-260915"
        let quick = body(.doubao, model: model)
        XCTAssertEqual(thinking(quick), "disabled")
        XCTAssertNil(effort(quick))
        XCTAssertEqual(quick["max_tokens"] as? Int, 16_000, "The default answer limit is 4K tokens")
        let professional = body(.doubao, model: model, mode: .professional)
        XCTAssertEqual(thinking(professional), "enabled")
        XCTAssertEqual(effort(professional), "low")
        let high = body(.doubao, model: model, reasoning: .high)
        XCTAssertEqual(thinking(high), "enabled")
        XCTAssertEqual(effort(high), "high")
        let off = body(.doubao, model: model, reasoning: .off, mode: .professional)
        XCTAssertEqual(thinking(off), "disabled")
        XCTAssertNil(effort(off))
        // An endpoint id or a model added by hand gets nothing unless the user chooses.
        XCTAssertEqual(body(.doubao, model: "ep-20260101-abcde").count, 1)
        XCTAssertEqual(effort(body(.doubao, model: "ep-20260101-abcde", reasoning: .medium)), "medium")
    }

    func testKimiAlwaysThinksAndTakesThreeSteps() {
        for model in ["kimi-k3.1-pro", "kimi-k3.1-pro-highspeed", "kimi-k3"] {
            for mode in [TranslationMode.quick, .professional] {
                let automatic = body(.kimi, model: model, mode: mode)
                XCTAssertEqual(effort(automatic), "low")
                XCTAssertNil(automatic["thinking"])
                XCTAssertEqual(automatic["max_tokens"] as? Int, 16_000)
                XCTAssertNil(automatic["temperature"])
            }
        }
        let expected: [ReasoningEffort: String] = [.off: "low", .low: "low", .medium: "high", .high: "max"]
        for (choice, sent) in expected {
            let chosen = body(.kimi, model: "kimi-k3.1-pro", reasoning: choice)
            XCTAssertEqual(effort(chosen), sent)
            XCTAssertNil(chosen["thinking"])
        }
    }

    func testZhipuDiffersByModelFamily() {
        let flash = body(.zhipu, model: "glm-5.3-flash")
        XCTAssertEqual(effort(flash), "low")
        XCTAssertNil(flash["thinking"])
        XCTAssertNil(flash["max_tokens"], "The default limit is already 65536")
        XCTAssertEqual(effort(body(.zhipu, model: "glm-5.3", reasoning: .off)), "low")
        XCTAssertEqual(effort(body(.zhipu, model: "glm-5.3", reasoning: .medium)), "high")
        XCTAssertEqual(effort(body(.zhipu, model: "GLM-5.3-FlashX", reasoning: .high)), "max")

        let quick = body(.zhipu, model: "glm-5.2")
        XCTAssertEqual(thinking(quick), "disabled")
        XCTAssertNil(effort(quick))
        let professional = body(.zhipu, model: "glm-5.2", mode: .professional)
        XCTAssertEqual(thinking(professional), "enabled")
        XCTAssertEqual(effort(professional), "low")
        let medium = body(.zhipu, model: "glm-5.2", reasoning: .medium)
        XCTAssertEqual(thinking(medium), "enabled")
        XCTAssertEqual(effort(medium), "medium")
        XCTAssertEqual(thinking(body(.zhipu, model: "glm-5.2", reasoning: .off)), "disabled")

        // Earlier models only switch thinking on or off.
        XCTAssertEqual(body(.zhipu, model: "glm-4.7").count, 1)
        let older = body(.zhipu, model: "glm-4.7", reasoning: .high)
        XCTAssertEqual(thinking(older), "enabled")
        XCTAssertNil(effort(older))
    }

    func testMiniMax() {
        let flash = body(.minimax, model: "MiniMax-M3.1-Flash")
        XCTAssertEqual(effort(flash), "low")
        XCTAssertNil(flash["thinking"], "Turning thinking off is refused by this model")
        XCTAssertEqual(flash["reasoning_split"] as? Bool, true)
        XCTAssertEqual(flash["max_completion_tokens"] as? Int, 32_000)
        XCTAssertNil(flash["max_tokens"])
        XCTAssertEqual(effort(body(.minimax, model: "MiniMax-M3.1-Flash", reasoning: .off)), "low")
        XCTAssertEqual(effort(body(.minimax, model: "MiniMax-M3.1-Flash", reasoning: .high)), "high")

        let quick = body(.minimax, model: "MiniMax-M3")
        XCTAssertEqual(thinking(quick), "disabled")
        XCTAssertNil(effort(quick))
        XCTAssertEqual(quick["reasoning_split"] as? Bool, true)
        XCTAssertNil(body(.minimax, model: "MiniMax-M3", mode: .professional)["thinking"], "Adaptive thinking is the model's default")
        let low = body(.minimax, model: "MiniMax-M3", reasoning: .low)
        XCTAssertEqual(thinking(low), "adaptive")
        XCTAssertNil(effort(low))
        XCTAssertEqual(thinking(body(.minimax, model: "MiniMax-M3", reasoning: .off, mode: .professional)), "disabled")
    }

    func testOtherFormatsAndCustomServicesGetNoProviderFields() {
        XCTAssertEqual(body(.kimi, model: "kimi-k3.1-pro", style: .anthropicMessages).count, 1)
        XCTAssertEqual(body(.minimax, model: "MiniMax-M3", style: .responses).count, 1)
        XCTAssertEqual(body(.custom, model: "kimi-k3.1-pro").count, 1)
        var settings = AppSettings()
        settings.activeID = "custom-1"
        settings.configuration = ProviderConfiguration(provider: .custom)
        settings.configuration.model = "doubao-seed-2-1-lite-260915"
        var request: [String: Any] = ["model": settings.configuration.model]
        APIClient.applyOutputLimits(to: &request, settings: settings, configuration: settings.configuration, model: settings.configuration.model)
        APIClient.applyReasoning(to: &request, settings: settings, configuration: settings.configuration, model: settings.configuration.model)
        XCTAssertEqual(request.count, 1, "An extra custom service is treated like the built-in custom entry")
    }

    func testTextOnlyModelsAreKnownBeforeAnImageIsSent() {
        XCTAssertTrue(APIClient.isTextOnly("glm-5.3", provider: .zhipu))
        XCTAssertTrue(APIClient.isTextOnly("GLM-5.3", provider: .zhipu))
        XCTAssertFalse(APIClient.isTextOnly("glm-5.3-flash", provider: .zhipu))
        XCTAssertTrue(APIClient.isTextOnly("deepseek-v4-pro", provider: .deepSeek))
        XCTAssertFalse(APIClient.isTextOnly("deepseek-flash", provider: .deepSeek))
        XCTAssertFalse(APIClient.isTextOnly("glm-5.3", provider: .custom))
    }
}
