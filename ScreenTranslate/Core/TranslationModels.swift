import Foundation

enum APIStyle: String, Codable, CaseIterable, Identifiable {
    case chatCompletions, responses, anthropicMessages
    var id: String { rawValue }
    var title: String {
        switch self { case .responses: return "Responses"; case .chatCompletions: return "Chat Completions"; case .anthropicMessages: return "Claude Messages" }
    }
    var route: String {
        switch self { case .responses: return "responses"; case .chatCompletions: return "chat/completions"; case .anthropicMessages: return "messages" }
    }
}

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openAI, deepSeek, gemini, claude, qwen, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAI: return "OpenAI"; case .deepSeek: return "DeepSeek"
        case .gemini: return "Google Gemini"; case .claude: return "Anthropic Claude"
        case .qwen: return "通义千问"; case .custom: return "自定义 API"
        }
    }
    var defaultURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .deepSeek: return "https://api.deepseek.com"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .claude: return "https://api.anthropic.com/v1"
        case .qwen: return "https://dashscope-us.aliyuncs.com/compatible-mode/v1"
        case .custom: return ""
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
        case .claude: return [.init("claude-haiku-4-5", "Claude Haiku 4.5", "轻量翻译"), .init("claude-sonnet-5-5", "Claude Sonnet 5.5", "复杂语境")]
        case .qwen: return [.init("qwen-plus", "Qwen Plus", "日常翻译"), .init("qwen-turbo", "Qwen Turbo", "轻量翻译"), .init("qwen-max", "Qwen Max", "复杂语境")]
        case .custom: return []
        }
    }
    var setupNote: String {
        self == .qwen ? "默认美国区域，密钥需与区域一致。其他区域请在高级设置填写控制台给出的地址。"
            : "已填入官方地址。选择模型、填写 API Key，测试后保存。"
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
        }
        return URL(string: url)!
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

struct ProviderConfiguration: Codable, Equatable {
    var baseURL: String
    var model: String
    var style: APIStyle
    init(provider: AIProvider) {
        baseURL = provider.defaultURL
        model = provider.models.first?.id ?? ""
        style = provider.defaultStyle
    }
}

struct AppSettings: Codable, Equatable {
    var provider: AIProvider = .deepSeek
    var configurations: [String: ProviderConfiguration] = [:]
    var source: SourceLanguage = .automatic
    var target: TargetLanguage = .english
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
    var historyLimit: Int = 30
    var appearance: AppAppearance = .system
    var accentTheme: AccentTheme = .blue
    var reader = ReaderPreferences()
    var customAccent: ThemeRGB = .hex(0x2B5F94)
    var allowedModes: [TranslationMode] { translationService == .system ? [.quick] : TranslationMode.allCases }

    mutating func normalizePreferences() {
        if translationService == .system { mode = .quick; askModeInShortcuts = false }
        if ![10, 30, 100].contains(historyLimit) { historyLimit = 30 }
        customAccent = customAccent.normalized
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
        case mode, quickEngine, askModeInShortcuts, cacheTranslations
        case translationService, historyLimit, appearance, accentTheme, customAccent, reader, modePrompts
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .deepSeek
        configurations = try values.decodeIfPresent([String: ProviderConfiguration].self, forKey: .configurations) ?? [:]
        source = try values.decodeIfPresent(SourceLanguage.self, forKey: .source) ?? .automatic
        // v1.0 had no source field and offered two additional target languages.
        // Migrate those targets to Chinese while retaining all API configuration.
        let savedTarget = try values.decodeIfPresent(String.self, forKey: .target)
        target = savedTarget.flatMap(TargetLanguage.init(rawValue:)) ?? (savedTarget == nil ? .english : .simplifiedChinese)
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
        historyLimit = try values.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 30
        appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        accentTheme = try values.decodeIfPresent(AccentTheme.self, forKey: .accentTheme) ?? .blue
        customAccent = try values.decodeIfPresent(ThemeRGB.self, forKey: .customAccent) ?? .hex(0x2B5F94)
        reader = try values.decodeIfPresent(ReaderPreferences.self, forKey: .reader) ?? ReaderPreferences()
        normalizePreferences()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(provider, forKey: .provider); try values.encode(configurations, forKey: .configurations)
        try values.encode(source, forKey: .source); try values.encode(target, forKey: .target)
        try values.encode(tone, forKey: .tone); try values.encode(glossary, forKey: .glossary)
        try values.encode(customPrompt, forKey: .customPrompt); try values.encode(saveRecentResult, forKey: .saveRecentResult)
        try values.encode(modePrompts, forKey: .modePrompts)
        try values.encode(cleanScreenText, forKey: .cleanScreenText); try values.encode(mode, forKey: .mode)
        try values.encode(cacheTranslations, forKey: .cacheTranslations)
        try values.encode(quickEngine, forKey: .quickEngine); try values.encode(askModeInShortcuts, forKey: .askModeInShortcuts)
        try values.encode(preferSpeed, forKey: .preferSpeed); try values.encode(imageMode, forKey: .imageMode)
        try values.encode(translationService, forKey: .translationService); try values.encode(historyLimit, forKey: .historyLimit)
        try values.encode(appearance, forKey: .appearance); try values.encode(accentTheme, forKey: .accentTheme)
        try values.encode(customAccent.normalized, forKey: .customAccent)
        try values.encode(reader, forKey: .reader)
    }

    mutating func swapLanguages() {
        guard let previousSource = source.targetLanguage else { return }
        source = SourceLanguage(target: target)
        target = previousSource
    }

    var configuration: ProviderConfiguration {
        get { configurations[provider.rawValue] ?? ProviderConfiguration(provider: provider) }
        set { configurations[provider.rawValue] = newValue }
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
    var rawOCR: String? = nil
    // Only new visual results with actual local OCR may expose an original.
    // Old records containing a workflow explanation keep their original hidden.
    var visualOCR: Bool? = nil
    var mode: TranslationMode? = nil
    var blocks: [ReadingBlock]? = nil
    var usedCache: Bool? = nil
    var uncertainOCR: Bool? = nil
}

struct TranslationOutput: Equatable, Sendable {
    var text: String
    var warning: String?
    var blocks: [ReadingBlock]? = nil
}

enum TranslationError: LocalizedError, Equatable {
    case missingKey, missingModel, invalidURL, emptyText, tooMuchText, tooMuchGlossary, tooMuchPrompt
    case invalidImage, imageTooLarge, noText, malformedResponse, emptyResponse, visionUnsupported
    case http(Int), network, timeout, credentialUnavailable, persistence
    case incompleteLayout, imageRequired, systemUnavailable
    case modeUnavailable, incompleteTranslation

    var errorDescription: String? {
        switch self {
        case .missingKey: return "请在 API 设置中填写密钥并保存。"
        case .missingModel: return "请先在 API 设置中选择模型。"
        case .invalidURL: return "请使用完整的 HTTPS 地址，不要附加账号、查询参数或片段。"
        case .emptyText: return "请输入文字或选择包含清晰文字的图片。"
        case .tooMuchText: return "原文最多 16,000 字符，请裁剪图片或分段翻译。"
        case .tooMuchGlossary: return "术语表过长，请缩短到 4,000 字符以内。"
        case .tooMuchPrompt: return "提示词过长，请缩短到 8,000 字符以内。"
        case .invalidImage: return "无法读取图片，请使用 PNG、JPEG 或 HEIC 格式。"
        case .imageTooLarge: return "图片过大，请裁剪后重试（文件上限 25 MB）。"
        case .noText: return "没有识别到清晰文字。可以裁剪到文字区域再试，或切换识图模式获取画面大意。"
        case .visionUnsupported: return "当前模型不支持看图。请在 API 设置中选择支持图片输入的模型，或切回快速／专业模式。"
        case .malformedResponse: return "接口返回格式不兼容。请检查接口格式、API 地址和模型名称。"
        case .emptyResponse: return "模型没有返回译文。请换一个模型，或稍后重试。"
        case .http(let status):
            switch status {
            case 401: return "API Key 无效或已过期，请检查设置。（HTTP 401）"
            case 402: return "API 账户余额不足，请检查服务商账户。（HTTP 402）"
            case 403: return "此账户无权使用该服务或模型。（HTTP 403）"
            case 404: return "接口或模型不存在，请检查 API 地址和模型名称。（HTTP 404）"
            case 429: return "请求过于频繁或额度不足，请稍后重试。（HTTP 429）"
            case 500...599: return "AI 服务暂时不可用，请稍后重试。（HTTP \(status)）"
            default: return "请求被接口拒绝，请检查模型、接口格式及账户权限。（HTTP \(status)）"
            }
        case .network: return "无法连接 AI 服务，请检查网络和 API 地址。"
        case .timeout: return "翻译等待超时。请稍后重试，或选择响应更快的模型。"
        case .credentialUnavailable: return "无法访问安全存储。请解锁手机后重试，或重新保存 API Key。"
        case .persistence: return "无法保存设置或翻译记录，请检查设备的可用空间。"
        case .incompleteLayout: return "模型没有完整保留各段内容或数字，本次未生成全文。请重试或换一个模型；快速模式不校验段落结构。"
        case .imageRequired: return "识图模式需要一张图片。请先选择图片，或切换快速／专业模式翻译文字。"
        case .systemUnavailable: return "系统翻译需在真机的读屏 App 内使用，并按提示下载语言。此处未调用 API，请切换 AI API 后重试。"
        case .incompleteTranslation: return "AI 服务提前截断了译文，本次未生成全文。请重试或换一个模型。"
        case .modeUnavailable: return "系统翻译仅支持快速模式。请先在设置中将翻译服务切换为 AI API，再使用专业或识图模式。"
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
