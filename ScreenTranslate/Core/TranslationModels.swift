import Foundation

enum APIStyle: String, Codable, CaseIterable, Identifiable {
    case chatCompletions, responses, anthropicMessages
    var id: String { rawValue }
    var title: String {
        switch self { case .responses: return "Responses"; case .chatCompletions: return "Chat Completions"; case .anthropicMessages: return "Claude Messages" }
    }
    /// Name on the model page, in the words provider documents use.
    var displayName: String {
        switch self { case .chatCompletions: return "OpenAI 兼容"; case .responses: return "OpenAI Responses"; case .anthropicMessages: return "Claude 兼容" }
    }
    var route: String {
        switch self { case .responses: return "responses"; case .chatCompletions: return "chat/completions"; case .anthropicMessages: return "messages" }
    }
}

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openAI, deepSeek, gemini, claude, qwen, custom
    case doubao, kimi, zhipu, minimax
    var id: String { rawValue }

    /// Order on the 添加供应商 page: Claude, ChatGPT and DeepSeek first, then
    /// the rest, with no domestic/overseas split.
    static let presets: [AIProvider] = [.claude, .openAI, .deepSeek, .qwen, .doubao, .kimi, .zhipu, .minimax, .gemini]
    /// The providers versions up to 1.3.1 know.
    static let legacyCases: Set<AIProvider> = [.openAI, .deepSeek, .gemini, .claude, .qwen, .custom]
    /// A built-in provider's entry uses its raw value as id; any other id is a custom service.
    static func kind(of entryID: String) -> AIProvider { AIProvider(rawValue: entryID) ?? .custom }

    var title: String {
        switch self {
        case .openAI: return "ChatGPT"; case .deepSeek: return "DeepSeek"
        case .gemini: return "Gemini"; case .claude: return "Claude"
        case .qwen: return "通义千问"; case .custom: return "自定义 API"
        case .doubao: return "豆包"; case .kimi: return "Kimi"
        case .zhipu: return "智谱 GLM"; case .minimax: return "MiniMax"
        }
    }
    /// Who runs the service; the second line of a provider row.
    var subtitle: String {
        switch self {
        case .openAI: return "OpenAI"; case .deepSeek: return "深度求索 · 读屏的默认服务"
        case .gemini: return "Google"; case .claude: return "Anthropic"
        case .qwen: return "阿里云百炼"; case .custom: return "OpenAI 或 Claude 兼容接口"
        case .doubao: return "火山方舟"; case .kimi: return "月之暗面"
        case .zhipu: return "智谱 AI"; case .minimax: return "稀宇科技"
        }
    }
    var isRecommended: Bool { self == .deepSeek }
    var defaultURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .deepSeek: return "https://api.deepseek.com"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .claude: return "https://api.anthropic.com/v1"
        case .qwen: return "https://dashscope-us.aliyuncs.com/compatible-mode/v1"
        case .custom: return ""
        case .doubao: return "https://ark.cn-beijing.volces.com/api/v3"
        case .kimi: return "https://api.moonshot.cn/v1"
        case .zhipu: return "https://open.bigmodel.cn/api/paas/v4"
        case .minimax: return "https://api.minimax.cn/v1"
        }
    }
    var defaultStyle: APIStyle {
        self == .openAI ? .responses : (self == .claude ? .anthropicMessages : .chatCompletions)
    }
    var models: [ModelPreset] {
        switch self {
        case .openAI: return [.init("gpt-6-luna", "GPT-6 Luna", "日常翻译"), .init("gpt-6.1-sol", "GPT-6.1 Sol", "复杂语境"), .init("gpt-4.1-mini", "GPT-4.1 Mini", "轻量模型")]
        case .deepSeek: return [.init("deepseek-flash", "DeepSeek Flash", "日常翻译"), .init("deepseek-v4-pro", "DeepSeek V4 Pro", "复杂语境")]
        case .gemini: return [.init("gemini-3.8-flash", "Gemini 3.8 Flash", "日常翻译"), .init("gemini-3.5-flash-lite", "Gemini 3.5 Flash-Lite", "轻量翻译")]
        case .claude: return [.init("claude-haiku-5-5", "Claude Haiku 5.5", "日常翻译"), .init("claude-sonnet-5-5", "Claude Sonnet 5.5", "复杂语境"), .init("claude-opus-5-5", "Claude Opus 5.5", "疑难文本")]
        case .qwen: return [.init("qwen-plus", "Qwen Plus", "日常翻译"), .init("qwen-turbo", "Qwen Turbo", "轻量翻译"), .init("qwen-max", "Qwen Max", "复杂语境")]
        case .custom: return []
        case .doubao: return [.init("doubao-seed-2-1-lite-260915", "豆包 Seed 2.1 Lite", "日常翻译"), .init("doubao-seed-2-1-pro-260915", "豆包 Seed 2.1 Pro", "复杂语境")]
        case .kimi: return [.init("kimi-k3.1-pro", "Kimi K3.1 Pro", "日常翻译"), .init("kimi-k3.1-pro-highspeed", "Kimi K3.1 Pro 高速版", "更快")]
        case .zhipu: return [.init("glm-5.3-flash", "GLM-5.3 Flash", "日常翻译"), .init("glm-5.3", "GLM-5.3", "复杂语境，不能看图")]
        case .minimax: return [.init("MiniMax-M3.1-Flash", "MiniMax M3.1 Flash", "日常翻译"), .init("MiniMax-M3", "MiniMax M3", "复杂语境")]
        }
    }
    /// What to know about the address; shown under the key and address fields.
    var setupNote: String {
        switch self {
        case .qwen: return "默认是美国区域的地址，密钥要和区域一致。其他区域请把 API 地址改成控制台给出的地址。"
        case .doubao: return "默认是火山方舟（中国站）的地址。国际版 BytePlus 的地址和模型 ID 都不同，要用它请改 API 地址并手动添加模型。"
        case .kimi: return "默认是国内站的地址。国际站的密钥不通用，要用它请把 API 地址改成 https://api.moonshot.ai/v1。"
        case .zhipu: return "默认是国内站的地址。国际站 Z.AI 的密钥不通用，要用它请把 API 地址改成 https://api.z.ai/api/paas/v4。"
        case .minimax: return "默认是国内站的地址。国际站请把 API 地址改成 https://api.minimax.io/v1。"
        case .openAI, .deepSeek, .gemini, .claude, .custom: return "已填入官方地址，一般不用改。"
        }
    }
    var documentationURL: URL {
        let url: String
        switch self {
        case .openAI: url = "https://developers.openai.com/api/docs/models"
        case .deepSeek: url = "https://api-docs.deepseek.com/"
        case .gemini: url = "https://ai.google.dev/gemini-api/docs/openai"
        case .claude: url = "https://platform.claude.com/docs/en/models/overview"
        case .qwen: url = "https://www.alibabacloud.com/help/en/model-studio/compatibility-of-openai-with-dashscope"
        case .custom: url = "https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create"
        case .doubao: url = "https://docs.volcengine.com/docs/82379"
        case .kimi: url = "https://platform.kimi.com/docs"
        case .zhipu: url = "https://docs.bigmodel.cn"
        case .minimax: url = "https://platform.minimax.cn/docs"
        }
        return URL(string: url)!
    }
    /// The console page where a key is created, when the provider has a stable one.
    var keyURL: URL? {
        let url: String
        switch self {
        case .openAI: url = "https://platform.openai.com/api-keys"
        case .deepSeek: url = "https://platform.deepseek.com/api_keys"
        case .gemini: url = "https://aistudio.google.com/apikey"
        case .claude: url = "https://platform.claude.com/settings/keys"
        case .doubao: url = "https://ark.volcengine.com/region:cn-beijing/apiKey"
        case .kimi: url = "https://platform.kimi.com/console/api-keys"
        case .zhipu: url = "https://bigmodel.cn/usercenter/proj-mgmt/apikeys"
        case .minimax: url = "https://platform.minimax.cn/user-center/basic-information/interface-key"
        // 通义千问's console differs by region; the documentation link covers it.
        case .qwen, .custom: return nil
        }
        return URL(string: url)
    }
}

struct ModelPreset: Identifiable {
    var id: String
    var title: String
    var detail: String
    init(_ id: String, _ title: String, _ detail: String) { self.id = id; self.title = title; self.detail = detail }
}

enum TargetLanguage: String, Codable, CaseIterable, Identifiable {
    case simplifiedChinese = "简体中文", english = "English", japanese = "日本語"
    var languageCode: String { self == .simplifiedChinese ? "zh-Hans" : (self == .japanese ? "ja" : "en") }
    var id: String { rawValue }
    var title: String {
        switch self { case .simplifiedChinese: return "中文"; case .english: return "英语"; case .japanese: return "日语" }
    }
    var promptName: String {
        switch self { case .simplifiedChinese: return "Simplified Chinese"; case .english: return "English"; case .japanese: return "Japanese" }
    }
}

enum SourceLanguage: String, Codable, CaseIterable, Identifiable {
    case automatic = "auto", chinese = "zh", english = "en", japanese = "ja"
    var id: String { rawValue }
    var title: String {
        switch self { case .automatic: return "自动识别"; case .chinese: return "中文"; case .english: return "英语"; case .japanese: return "日语" }
    }
    var promptName: String {
        switch self { case .automatic: return "Auto-detect"; case .chinese: return "Chinese"; case .english: return "English"; case .japanese: return "Japanese" }
    }
    var targetLanguage: TargetLanguage? {
        switch self { case .automatic: return nil; case .chinese: return .simplifiedChinese; case .english: return .english; case .japanese: return .japanese }
    }
    init(target: TargetLanguage) {
        switch target { case .simplifiedChinese: self = .chinese; case .english: self = .english; case .japanese: self = .japanese }
    }
    var recognitionLanguages: [String] {
        switch self {
        case .automatic: return ["ja-JP", "en-US", "zh-Hans", "zh-Hant"]
        case .chinese: return ["zh-Hans", "zh-Hant"]
        case .english: return ["en-US"]
        case .japanese: return ["ja-JP", "en-US"]
        }
    }
}

enum TranslationTone: String, Codable, CaseIterable, Identifiable {
    case natural = "自然表达", literal = "贴近原文"
    var id: String { rawValue }
    var title: String { self == .natural ? "自然表达" : "贴近原文" }
}

enum ImageTranslationMode: String, Codable, CaseIterable, Identifiable {
    case text, visual
    var id: String { rawValue }
    var title: String { self == .text ? "文字" : "识图" }
}

enum TranslationMode: String, Codable, CaseIterable, Identifiable {
    case quick, professional, visual
    var id: String { rawValue }
    var title: String {
        switch self { case .quick: return "快速"; case .professional: return "专业"; case .visual: return "识图" }
    }
    var detail: String {
        switch self {
        case .quick: return "快速、精炼地翻译全部内容。"
        case .professional: return "保留标题、段落、列表及价格关系。"
        case .visual: return "解释图片内文字和画面大意。"
        }
    }
}

enum TranslationService: String, Codable, CaseIterable, Identifiable {
    case api, system
    var id: String { rawValue }
    var title: String { self == .api ? "AI 翻译" : "系统翻译" }
}
typealias QuickTranslationEngine = TranslationService

/// User-selected reasoning depth. `nil` in a configuration means 自动: keep
/// the built-in, provider-specific behaviour and send nothing new.
enum ReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, low, medium, high
    var id: String { rawValue }
    var title: String {
        switch self { case .off: return "关闭"; case .low: return "低"; case .medium: return "中"; case .high: return "高" }
    }
}

extension AIProvider {
    /// 通义千问 only enables thinking in streaming mode, so it offers 关闭 only.
    var reasoningOptions: [ReasoningEffort] { self == .qwen ? [.off] : ReasoningEffort.allCases }
    var reasoningNote: String {
        switch self {
        case .openAI: return "自动：快速模式对已知模型降低推理。不支持推理的模型（如 GPT-4.1 Mini）请保持自动。"
        case .deepSeek: return "自动：快速模式关闭思考，专业和识图模式用低强度。"
        case .gemini: return "自动：快速模式对 Flash 系列用最低档（2.5 Flash 关闭思考）。Gemini 3 等无法完全关闭思考的模型，“关闭”会用最低档。"
        case .claude: return "自动：快速模式对 5 系列用低强度；专业和识图模式不发送思考参数（默认自适应思考）。Opus 5.5 无法关闭思考，“关闭”会改用最低强度。"
        case .qwen: return "通义千问的思考模式需要流式输出，这里只提供关闭。"
        case .custom: return "自动不发送任何推理参数；其他档位按所选接口格式发送标准字段。"
        case .doubao: return "自动：快速模式关闭思考，专业和识图模式用低强度。"
        case .kimi: return "K3 系列始终思考，无法关闭：自动和“关闭”都用最低档。"
        case .zhipu: return "GLM-5.3 系列无法关闭思考，自动和“关闭”都用最低档；GLM-5.2 可以关闭。"
        case .minimax: return "M3.1 Flash 无法关闭思考，自动和“关闭”都用最低档；M3 只能开或关，不分强度。"
        }
    }
}

/// One model kept under a provider, with the settings that belong to it.
struct SavedModel: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var style: APIStyle
    var reasoning: ReasoningEffort? = nil
    init(id: String, style: APIStyle, reasoning: ReasoningEffort? = nil) {
        self.id = id; self.style = style; self.reasoning = reasoning
    }
    private enum CodingKeys: String, CodingKey { case id, style, reasoning }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        style = try values.decode(APIStyle.self, forKey: .style)
        reasoning = (try? values.decodeIfPresent(ReasoningEffort.self, forKey: .reasoning)) ?? nil
    }
}

/// One provider entry. `model`, `style` and `reasoning` describe the model the
/// provider currently uses, which is what a request reads; `models` keeps the
/// other models and their own settings.
struct ProviderConfiguration: Codable, Equatable {
    var baseURL: String
    var model: String
    var style: APIStyle
    var reasoning: ReasoningEffort? = nil
    /// The user's own name for a custom service.
    var name: String? = nil
    /// `nil` until the list is first edited; the provider's presets stand in,
    /// so settings saved by earlier versions load without a migration.
    var models: [SavedModel]? = nil
    init(provider: AIProvider) {
        baseURL = provider.defaultURL
        model = provider.models.first?.id ?? ""
        style = provider.defaultStyle
    }
    private enum CodingKeys: String, CodingKey { case baseURL, model, style, reasoning, name, models }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        model = try values.decode(String.self, forKey: .model)
        style = try values.decode(APIStyle.self, forKey: .style)
        // Saved before 1.4.0, or written by a newer build: fall back to 自动.
        reasoning = (try? values.decodeIfPresent(ReasoningEffort.self, forKey: .reasoning)) ?? nil
        name = (try? values.decodeIfPresent(String.self, forKey: .name)) ?? nil
        models = (try? values.decodeIfPresent([SavedModel].self, forKey: .models)) ?? nil
    }
}

extension ProviderConfiguration {
    private var selectedID: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The fields a request depends on, without the name and the other models.
    var requestFields: ProviderConfiguration {
        var copy = self
        copy.name = nil; copy.models = nil
        return copy
    }

    /// Every model kept under this provider. The one in use carries the
    /// top-level settings, so code that edits `model` or `style` directly stays valid.
    func savedModels(for provider: AIProvider) -> [SavedModel] {
        var list: [SavedModel] = []
        for item in models ?? provider.models.map({ SavedModel(id: $0.id, style: style) }) {
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !list.contains(where: { $0.id == id }) else { continue }
            list.append(SavedModel(id: id, style: item.style, reasoning: item.reasoning))
        }
        let selected = selectedID
        guard !selected.isEmpty else { return list }
        let current = SavedModel(id: selected, style: style, reasoning: reasoning)
        if let index = list.firstIndex(where: { $0.id == selected }) { list[index] = current }
        else { list.insert(current, at: 0) }
        return list
    }

    /// Switches the provider to one of its kept models.
    mutating func select(_ id: String, provider: AIProvider) {
        let list = savedModels(for: provider)
        guard let item = list.first(where: { $0.id == id }) else { return }
        models = list
        model = item.id; style = item.style; reasoning = item.reasoning
    }

    /// Adds a model, or replaces the settings of one that is already kept.
    mutating func upsert(_ item: SavedModel, provider: AIProvider) {
        let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        var list = savedModels(for: provider)
        let clean = SavedModel(id: id, style: item.style, reasoning: item.reasoning)
        if let index = list.firstIndex(where: { $0.id == id }) { list[index] = clean } else { list.append(clean) }
        models = list
        if selectedID.isEmpty || selectedID == id { model = id; style = clean.style; reasoning = clean.reasoning }
    }

    /// Removes a model. When it was the one in use, the next kept model takes over.
    mutating func removeModel(_ id: String, provider: AIProvider) {
        var list = savedModels(for: provider)
        list.removeAll { $0.id == id }
        models = list
        guard selectedID == id else { return }
        if let next = list.first { model = next.id; style = next.style; reasoning = next.reasoning }
        else { model = ""; reasoning = nil }
    }
}

struct AppSettings: Codable, Equatable {
    /// The provider entry in use: a built-in provider's raw value, or the id
    /// of an extra custom service. It keys `configurations` and the keychain.
    var activeID: String = AIProvider.deepSeek.rawValue
    /// Kind of the entry in use. Setting it switches to that provider's own entry.
    var provider: AIProvider {
        get { AIProvider.kind(of: activeID) }
        set { activeID = newValue.rawValue }
    }
    /// Entries shown under 供应商, in order. `nil` for settings saved before
    /// the list existed; `listedProviderIDs(keyed:)` derives it then.
    var providerList: [String]? = nil
    var configurations: [String: ProviderConfiguration] = [:]
    var source: SourceLanguage = .automatic
    var target: TargetLanguage = .simplifiedChinese
    /// Which language text that is already in the target language goes to
    /// instead: the first one in this order that is not the target.
    var languagePriority: [TargetLanguage] = AppSettings.defaultLanguagePriority
    /// Applies `languagePriority` when the source is 自动识别.
    var smartTarget: Bool = true
    var tone: TranslationTone = .natural
    var glossary: String = ""
    // Keys use stable mode IDs; labels and the app name may change independently.
    var modePrompts: [String: String] = [:]
    var customPrompt: String {
        get { prompt(for: mode) }
        set { setPrompt(newValue, for: mode) }
    }
    func prompt(for mode: TranslationMode) -> String { modePrompts[mode.rawValue] ?? "" }
    mutating func setPrompt(_ prompt: String, for mode: TranslationMode) {
        if prompt.isEmpty { modePrompts.removeValue(forKey: mode.rawValue) }
        else { modePrompts[mode.rawValue] = prompt }
    }
    var saveRecentResult: Bool = true
    var cleanScreenText: Bool = true
    var cacheTranslations: Bool = true
    var mode: TranslationMode = .quick
    var translationService: TranslationService = .api
    var quickEngine: QuickTranslationEngine {
        get { translationService }
        set { translationService = newValue }
    }
    var askModeInShortcuts: Bool = false
    /// 原图直译: draw translations over the screenshot. Off by default; it makes
    /// quick mode send numbered blocks (more tokens, slower) instead of plain text.
    var imageOverlay: Bool = false
    var historyLimit: Int = 30
    var appearance: AppAppearance = .system
    var accentTheme: AccentTheme = .blue
    var reader = ReaderPreferences()
    var customAccent: ThemeRGB = .hex(0x2B5F94)
    var allowedModes: [TranslationMode] { translationService == .system ? [.quick] : TranslationMode.allCases }

    mutating func normalizePreferences() {
        if translationService == .system { mode = .quick; askModeInShortcuts = false }
        if ![10, 30, 100].contains(historyLimit) { historyLimit = 30 }
        languagePriority = Self.normalizedPriority(languagePriority)
        customAccent = customAccent.normalized
        reader.normalize()
        modePrompts = modePrompts.filter { TranslationMode(rawValue: $0.key) != nil && !$0.value.isEmpty }
    }
    // Compatibility for pre-1.6 settings and callers. Mode is the single source of truth.
    var preferSpeed: Bool {
        get { mode == .quick }
        set { if mode != .visual { mode = newValue ? .quick : .professional } }
    }
    var imageMode: ImageTranslationMode {
        get { mode == .visual ? .visual : .text }
        set { if newValue == .visual { mode = .visual } else if mode == .visual { mode = .quick } }
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case provider, configurations, source, target, tone, glossary, customPrompt, saveRecentResult
        case cleanScreenText, preferSpeed, imageMode
        case mode, quickEngine, askModeInShortcuts, cacheTranslations, imageOverlay
        case translationService, historyLimit, appearance, accentTheme, customAccent, reader, modePrompts
        case activeProvider, providerList = "providers"
        case languagePriority, smartTarget
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // `provider` is the key earlier versions read; `activeProvider` is only
        // written when it says more (see `encode`).
        let saved = try values.decodeIfPresent(String.self, forKey: .activeProvider)
            ?? values.decodeIfPresent(String.self, forKey: .provider) ?? ""
        activeID = saved.isEmpty ? AIProvider.deepSeek.rawValue : saved
        providerList = try values.decodeIfPresent([String].self, forKey: .providerList)
        configurations = try values.decodeIfPresent([String: ProviderConfiguration].self, forKey: .configurations) ?? [:]
        source = try values.decodeIfPresent(SourceLanguage.self, forKey: .source) ?? .automatic
        // v1.0 had no source field and offered two additional target languages.
        // Migrate those targets to Chinese while retaining all API configuration.
        let savedTarget = try values.decodeIfPresent(String.self, forKey: .target)
        target = savedTarget.flatMap(TargetLanguage.init(rawValue:)) ?? .simplifiedChinese
        // Saved as raw strings so a language this version does not know is dropped, not fatal.
        let savedPriority = try values.decodeIfPresent([String].self, forKey: .languagePriority) ?? []
        languagePriority = savedPriority.compactMap(TargetLanguage.init(rawValue:))
        smartTarget = try values.decodeIfPresent(Bool.self, forKey: .smartTarget) ?? true
        tone = try values.decodeIfPresent(TranslationTone.self, forKey: .tone) ?? .natural
        glossary = try values.decodeIfPresent(String.self, forKey: .glossary) ?? ""
        let legacyPrompt = try values.decodeIfPresent(String.self, forKey: .customPrompt) ?? ""
        if let prompts = try values.decodeIfPresent([String: String].self, forKey: .modePrompts) {
            modePrompts = prompts
        } else if !legacyPrompt.isEmpty {
            // The previous global prompt applied to every mode. Preserve that
            // behaviour on upgrade, then allow each mode to diverge or reset.
            modePrompts = Dictionary(uniqueKeysWithValues: TranslationMode.allCases.map { ($0.rawValue, legacyPrompt) })
        }
        saveRecentResult = try values.decodeIfPresent(Bool.self, forKey: .saveRecentResult) ?? true
        cleanScreenText = try values.decodeIfPresent(Bool.self, forKey: .cleanScreenText) ?? true
        cacheTranslations = try values.decodeIfPresent(Bool.self, forKey: .cacheTranslations) ?? true
        let oldSpeed = try values.decodeIfPresent(Bool.self, forKey: .preferSpeed) ?? true
        let oldImage = try values.decodeIfPresent(ImageTranslationMode.self, forKey: .imageMode) ?? .text
        mode = try values.decodeIfPresent(TranslationMode.self, forKey: .mode)
            ?? (oldImage == .visual ? .visual : (oldSpeed ? .quick : .professional))
        let legacyEngine = try values.decodeIfPresent(TranslationService.self, forKey: .quickEngine) ?? .api
        translationService = try values.decodeIfPresent(TranslationService.self, forKey: .translationService)
            ?? (mode == .quick ? legacyEngine : .api)
        askModeInShortcuts = try values.decodeIfPresent(Bool.self, forKey: .askModeInShortcuts) ?? false
        imageOverlay = try values.decodeIfPresent(Bool.self, forKey: .imageOverlay) ?? false
        historyLimit = try values.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 30
        appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        accentTheme = try values.decodeIfPresent(AccentTheme.self, forKey: .accentTheme) ?? .blue
        customAccent = try values.decodeIfPresent(ThemeRGB.self, forKey: .customAccent) ?? .hex(0x2B5F94)
        reader = try values.decodeIfPresent(ReaderPreferences.self, forKey: .reader) ?? ReaderPreferences()
        normalizePreferences()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        // Versions up to 1.3.1 drop every setting when `provider` holds a value
        // they do not know, so that key only ever carries one of their six.
        let legacy = AIProvider.legacyCases.contains(provider) ? provider : .custom
        try values.encode(legacy, forKey: .provider)
        if activeID != legacy.rawValue { try values.encode(activeID, forKey: .activeProvider) }
        try values.encodeIfPresent(providerList, forKey: .providerList)
        try values.encode(configurations, forKey: .configurations)
        try values.encode(source, forKey: .source); try values.encode(target, forKey: .target)
        try values.encode(tone, forKey: .tone); try values.encode(glossary, forKey: .glossary)
        try values.encode(customPrompt, forKey: .customPrompt); try values.encode(saveRecentResult, forKey: .saveRecentResult)
        try values.encode(modePrompts, forKey: .modePrompts)
        try values.encode(cleanScreenText, forKey: .cleanScreenText); try values.encode(mode, forKey: .mode)
        try values.encode(cacheTranslations, forKey: .cacheTranslations)
        try values.encode(quickEngine, forKey: .quickEngine); try values.encode(askModeInShortcuts, forKey: .askModeInShortcuts)
        try values.encode(imageOverlay, forKey: .imageOverlay)
        try values.encode(preferSpeed, forKey: .preferSpeed); try values.encode(imageMode, forKey: .imageMode)
        try values.encode(translationService, forKey: .translationService); try values.encode(historyLimit, forKey: .historyLimit)
        try values.encode(appearance, forKey: .appearance); try values.encode(accentTheme, forKey: .accentTheme)
        try values.encode(customAccent.normalized, forKey: .customAccent)
        try values.encode(reader, forKey: .reader)
        try values.encode(languagePriority.map(\.rawValue), forKey: .languagePriority)
        try values.encode(smartTarget, forKey: .smartTarget)
    }

    mutating func swapLanguages() {
        guard let previousSource = source.targetLanguage else { return }
        source = SourceLanguage(target: target)
        target = previousSource
    }

    var configuration: ProviderConfiguration {
        get { configurations[activeID] ?? ProviderConfiguration(provider: provider) }
        set { configurations[activeID] = newValue }
    }
}

// MARK: - Provider entries

extension AppSettings {
    func configuration(for entryID: String) -> ProviderConfiguration {
        configurations[entryID] ?? ProviderConfiguration(provider: AIProvider.kind(of: entryID))
    }

    /// The user's own name for a custom service, otherwise the provider's name.
    func displayName(for entryID: String) -> String {
        let name = configurations[entryID]?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? AIProvider.kind(of: entryID).title : name
    }

    /// Recorded with each translation, e.g. "DeepSeek · deepseek-flash".
    var engineLabel: String { "\(displayName(for: activeID)) · \(configuration.model)" }

    func savedModels(for entryID: String) -> [SavedModel] {
        configuration(for: entryID).savedModels(for: AIProvider.kind(of: entryID))
    }

    /// Entries under 供应商. Settings saved before the list existed show the
    /// providers that were set up: the one in use and those in `keyed`, the
    /// entries that have an API key.
    func listedProviderIDs(keyed: Set<String>) -> [String] {
        var list: [String] = []
        func add(_ id: String) { if !id.isEmpty, !list.contains(id) { list.append(id) } }
        if let providerList {
            providerList.forEach(add)
        } else {
            for provider in AIProvider.presets + [.custom]
            where provider.rawValue == activeID || keyed.contains(provider.rawValue) {
                add(provider.rawValue)
            }
        }
        add(activeID)
        return list
    }

    /// Adds an entry and returns its id. A built-in provider has one entry;
    /// custom services can have several.
    @discardableResult
    mutating func addProvider(_ kind: AIProvider, configuration: ProviderConfiguration, keyed: Set<String>,
                              newID: () -> String = { "custom-" + UUID().uuidString.lowercased() }) -> String {
        var list = listedProviderIDs(keyed: keyed)
        let id = kind == .custom && list.contains(kind.rawValue) ? newID() : kind.rawValue
        if !list.contains(id) { list.append(id) }
        providerList = list
        configurations[id] = configuration
        return id
    }

    /// Removes an entry and its settings. The entry in use cannot be removed.
    @discardableResult
    mutating func removeProvider(_ entryID: String, keyed: Set<String>) -> Bool {
        guard entryID != activeID else { return false }
        providerList = listedProviderIDs(keyed: keyed).filter { $0 != entryID }
        configurations.removeValue(forKey: entryID)
        return true
    }

    /// Makes an entry the one in use, optionally switching it to one of its models.
    mutating func activate(_ entryID: String, model: String? = nil) {
        activeID = entryID
        guard let model else { return }
        updateConfiguration(for: entryID) { $0.select(model, provider: AIProvider.kind(of: entryID)) }
    }

    mutating func updateConfiguration(for entryID: String, _ change: (inout ProviderConfiguration) -> Void) {
        var value = configuration(for: entryID)
        change(&value)
        configurations[entryID] = value
    }

    /// True for the one model translations currently use.
    func isInUse(model: String, of entryID: String) -> Bool {
        entryID == activeID && configuration.model.trimmingCharacters(in: .whitespacesAndNewlines) == model
    }
}

struct TranslationResult: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var date: Date = Date()
    var original: String
    var translated: String
    var sourceLanguages: String
    var target: String
    var engine: String
    var elapsed: TimeInterval
    var warning: String?
    var imageMode: ImageTranslationMode? = nil
    var recognitionSeconds: TimeInterval? = nil
    var requestSeconds: TimeInterval? = nil
    var preparationSeconds: TimeInterval? = nil
    var refinementSeconds: TimeInterval? = nil
    var rawOCR: String? = nil
    // Only new visual results with actual local OCR may expose an original.
    // Old records containing a workflow explanation keep their original hidden.
    var visualOCR: Bool? = nil
    var mode: TranslationMode? = nil
    var blocks: [ReadingBlock]? = nil
    var usedCache: Bool? = nil
    var uncertainOCR: Bool? = nil
    /// Why the target differs from the one selected, when 语言优先级 changed it.
    var targetNote: String? = nil
}

struct TranslationOutput: Equatable, Sendable {
    var text: String
    var warning: String?
    var blocks: [ReadingBlock]? = nil
}

enum TranslationError: LocalizedError, Equatable {
    case missingKey, missingModel, invalidURL, emptyText, tooMuchText, tooMuchGlossary, tooMuchPrompt
    case invalidImage, imageTooLarge, clipboardImageUnavailable, noText, malformedResponse, emptyResponse, visionUnsupported, unexpectedLanguage
    case http(Int), network, timeout, credentialUnavailable, persistence
    /// An HTTP failure with the provider's own (sanitised, shortened) message.
    case httpDetail(Int, String)
    /// The provider reported an error after a streamed reply had started.
    case streamFailure(String)
    case incompleteLayout, imageRequired, systemUnavailable
    case modeUnavailable, incompleteTranslation
    case systemLanguageUnsupported, incompleteSystemTranslation
    case reviewUnavailable, reviewConflict, reviewColumns

    var errorDescription: String? {
        switch self {
        case .missingKey: return "还没有填 API Key。请到“设置 › AI 大模型”给正在用的供应商填写。"
        case .missingModel: return "还没有选模型。请到“设置 › AI 大模型”选一个。"
        case .invalidURL: return "请使用完整的 HTTPS 地址，不要附加账号、查询参数或片段。"
        case .emptyText: return "请输入文字或选择包含清晰文字的图片。"
        case .tooMuchText: return "原文最多 16,000 字符，请裁剪图片或分段翻译。"
        case .tooMuchGlossary: return "术语表过长，请缩短到 4,000 字符以内。"
        case .tooMuchPrompt: return "提示词过长，请缩短到 8,000 字符以内。"
        case .invalidImage: return "无法读取图片，请使用 PNG、JPEG 或 HEIC 格式。"
        case .clipboardImageUnavailable: return "未能读取剪贴板中的图片，请重新复制图片，或保存到照片后选择。"
        case .imageTooLarge: return "图片过大，请裁剪后重试（文件上限 25 MB）。"
        case .noText: return "没有识别到清晰文字。可以裁剪到文字区域再试，或切换识图模式获取画面大意。"
        case .visionUnsupported: return "当前模型不支持看图。请到“设置 › AI 大模型”换一个能看图的模型，或切回快速／专业模式。"
        case .malformedResponse: return "接口返回格式不兼容。请检查接口格式、API 地址和模型名称。"
        case .unexpectedLanguage: return "模型未按所选目标语言输出，请重试或更换模型。"
        case .emptyResponse: return "模型没有返回译文。请换一个模型，或稍后重试。"
        case .http(let status): return Self.httpMessage(status)
        case .httpDetail(let status, let detail): return Self.httpMessage(status) + "\n服务商原话：\(detail)"
        case .streamFailure(let detail): return "AI 服务在返回译文途中报错，本次未生成全文。请重试。\n服务商原话：\(detail)"
        case .network: return "无法连接 AI 服务，请检查网络和 API 地址。"
        case .timeout: return "翻译等待超时。请稍后重试，或选择响应更快的模型。"
        case .credentialUnavailable: return "无法访问安全存储。请解锁手机后重试，或重新保存 API Key。"
        case .persistence: return "无法保存设置或翻译记录，请检查设备的可用空间。"
        case .incompleteLayout: return "译文没有完整对应原文段落或数字，请重试或更换模型。"
        case .imageRequired: return "识图模式需要一张图片。请先选择图片，或切换快速／专业模式翻译文字。"
        case .systemUnavailable: return "系统翻译需在真机的读屏 App 内使用，并按提示下载语言。此处未调用 API，请切换 AI API 后重试。"
        case .systemLanguageUnsupported: return "此语言组合暂不支持本机翻译。请明确选择原文语言，或更换目标语言。"
        case .incompleteSystemTranslation: return "系统翻译未返回全部段落，请重试。"
        case .incompleteTranslation: return "AI 服务提前截断了译文，本次未生成全文。请重试或换一个模型。"
        case .modeUnavailable: return "系统翻译仅支持快速模式。请先在设置中将翻译服务切换为 AI API，再使用专业或识图模式。"
        case .reviewUnavailable: return "这条译文没有对应段落的原文，暂时无法逐段核对。请重新翻译图片，或使用专业模式翻译文字。"
        case .reviewConflict: return "译文或翻译记录已发生变化，请关闭核对界面后重新打开。"
        case .reviewColumns: return "请保留表格的列数；每个输入框对应原表的一列。"
        }
    }

    private static func httpMessage(_ status: Int) -> String {
        switch status {
        case 401: return "API Key 无效或已过期，请检查设置。（HTTP 401）"
        case 402: return "API 账户余额不足，请检查服务商账户。（HTTP 402）"
        case 403: return "此账户无权使用该服务或模型。（HTTP 403）"
        case 404: return "接口或模型不存在，请检查 API 地址和模型名称。（HTTP 404）"
        case 429: return "请求过于频繁或额度不足，请稍后重试。（HTTP 429）"
        case 500...599: return "AI 服务暂时不可用，请稍后重试。（HTTP \(status)）"
        default: return "请求被接口拒绝，请检查模型、接口格式及账户权限。（HTTP \(status)）"
        }
    }
}

enum TextPreparation {
    static let maximumCharacters = 16_000
    static let maximumPromptCharacters = 8_000
    static var promptExample: String { promptExample(for: .professional) }
    static func promptExample(for mode: TranslationMode) -> String {
        switch mode {
        case .quick: return "Translate into {target_language}. Keep all facts, names and numbers. Use short, natural phrases; no commentary.\n{glossary}"
        case .professional: return "Translate from {source_language} into {target_language}. Use {tone} wording. Keep headings concise, lists separate, and prices beside their items. Preserve every condition and paragraph.\n{glossary}"
        case .visual: return "Explain the readable text and the overall image in {target_language}. Keep item names, amounts and restrictions precise. Describe the scene briefly; identify uncertain details without guessing.\n{glossary}"
        }
    }
    static func expandedPrompt(_ prompt: String, settings: AppSettings) -> String {
        // One pass: replacement values (especially the glossary) are never interpreted as templates.
        let values = ["{source_language}": settings.source.promptName, "{target_language}": settings.target.promptName,
                      "{tone}": settings.tone == .natural ? "natural" : "literal", "{glossary}": settings.glossary]
        let pattern = "\\{(?:source_language|target_language|tone|glossary)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return prompt }
        var result = prompt
        for match in regex.matches(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let token = String(result[range])
            result.replaceSubrange(range, with: values[token] ?? token)
        }
        return result
    }
    static func recognitionWords(glossary: String) -> [String] {
        var found: [String] = []
        for line in glossary.components(separatedBy: .newlines) {
            let term = line.components(separatedBy: "→").first?
                .components(separatedBy: "=>").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if (2...80).contains(term.count), !found.contains(term) { found.append(term) }
            if found.count == 100 { break }
        }
        return found
    }
    static func validated(_ text: String) throws -> String {
        let clean = text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw TranslationError.emptyText }
        guard clean.count <= maximumCharacters else { throw TranslationError.tooMuchText }
        return clean
    }

    static func validatePreferences(_ settings: AppSettings) throws {
        guard settings.glossary.count <= 4_000 else { throw TranslationError.tooMuchGlossary }
        guard settings.customPrompt.count <= maximumPromptCharacters else { throw TranslationError.tooMuchPrompt }
    }

    static func instructions(settings: AppSettings) throws -> String {
        try validatePreferences(settings)
        return TranslationPrompts.text(settings: settings)
    }

    static func imageInstructions(settings: AppSettings) throws -> String {
        try validatePreferences(settings)
        return TranslationPrompts.visual(settings: settings)
    }
}
