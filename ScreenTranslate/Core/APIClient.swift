import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct APIClient {
    static let liveSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 120
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()
    let session: URLSession
    init(session: URLSession = APIClient.liveSession) { self.session = session }

    static func endpoint(configuration: ProviderConfiguration, models: Bool = false) throws -> URL {
        let input = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: input),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw TranslationError.invalidURL
        }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        // Accept either an API base URL or a full endpoint without appending it twice.
        for suffix in ["/chat/completions", "/responses", "/messages", "/models"] where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
            break
        }
        components.path = path + "/" + (models ? "models" : configuration.style.route)
        guard let url = components.url else { throw TranslationError.invalidURL }
        return url
    }

    typealias PartialHandler = @Sendable (String) -> Void

    /// Opens the connection to the provider while OCR runs, so the translation
    /// request does not wait for DNS, TCP and TLS. The request carries no key,
    /// header or content, and its reply is ignored. Only the live session is
    /// warmed; tests and fixtures supply their own session.
    func warmUp(configuration: ProviderConfiguration) {
        guard session === Self.liveSession, let request = Self.warmUpRequest(configuration: configuration) else { return }
        session.dataTask(with: request).resume()
    }

    static func warmUpRequest(configuration: ProviderConfiguration) -> URLRequest? {
        guard let url = try? endpoint(configuration: configuration) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        return request
    }

    /// Translates `text`. Long text without an image is split into a few
    /// concurrent requests. When `onPartial` is set the reply is streamed and
    /// `onPartial` receives readable text as it arrives; that preview is never
    /// the final result, which passes the same checks as a non-streamed reply.
    func translate(_ text: String, settings: AppSettings, apiKey: String,
                   timeout: TimeInterval = 25, imageJPEG: Data? = nil, fromImageText: Bool = false,
                   preserveBlocks: Bool = false, readingBlocks: [ReadingBlock]? = nil,
                   imageDetails: [Data] = [], onPartial: PartialHandler? = nil) async throws -> TranslationOutput {
        try Task.checkCancellation()
        guard imageDetails.isEmpty || imageJPEG != nil else { throw TranslationError.invalidImage }
        let detailBytes: Int = imageDetails.reduce(0) { total, data in total + data.count }
        let imageBytes: Int = (imageJPEG?.count ?? 0) + detailBytes
        guard imageDetails.count <= 2, imageBytes <= 8_388_608 else { throw TranslationError.imageTooLarge }
        let clean = try TextPreparation.validated(text)
        let layoutMode = preserveBlocks && imageJPEG == nil
        let request = Request(settings: settings, apiKey: apiKey, timeout: timeout, fromImageText: fromImageText)
        let output: TranslationOutput
        if imageJPEG == nil, clean.count > TranslationChunking.threshold,
           let chunked = try await translateInChunks(clean, layoutMode: layoutMode, readingBlocks: readingBlocks,
                                                     request: request, onPartial: onPartial) {
            output = chunked
        } else {
            let layout = layoutMode ? ProfessionalLayout(clean, readingBlocks: readingBlocks) : nil
            output = try await translateOnce(clean, layout: layout, request: request,
                                             imageJPEG: imageJPEG, imageDetails: imageDetails, onPartial: onPartial)
        }
        try Self.validateOutputLanguage(output.text, target: settings.target, fromImage: imageJPEG != nil)
        return output
    }

    /// The parts of a translation request shared by every chunk.
    private struct Request: Sendable {
        var settings: AppSettings
        var apiKey: String
        var timeout: TimeInterval
        var fromImageText: Bool
    }

    /// Returns nil when the text fits in one request.
    private func translateInChunks(_ clean: String, layoutMode: Bool, readingBlocks: [ReadingBlock]?,
                                   request: Request, onPartial: PartialHandler?) async throws -> TranslationOutput? {
        if layoutMode {
            let groups = TranslationChunking.blockGroups(readingBlocks ?? ReadingBlock.plainText(clean))
            guard groups.count > 1 else { return nil }
            var offsets: [Int] = []
            var total = 0
            for group in groups { offsets.append(total); total += group.count }
            let collector = onPartial.map {
                PartialTextCollector(count: groups.count, separators: Array(repeating: "\n\n", count: groups.count - 1), emit: $0)
            }
            let outputs = try await TranslationChunking.run(count: groups.count) { index in
                let group = groups[index]
                let text = group.map(\.text).joined(separator: "\n\n")
                let partial: PartialHandler? = collector.map { collector in { @Sendable text in collector.update(index, text) } }
                return try await self.translateOnce(text, layout: ProfessionalLayout(text, readingBlocks: group),
                                                    request: request, imageJPEG: nil, imageDetails: [], onPartial: partial)
            }
            var blocks: [ReadingBlock] = []
            for (index, output) in outputs.enumerated() {
                // Each request numbers its blocks from 1; restore the global order.
                for var block in output.blocks ?? [] { block.id += offsets[index]; blocks.append(block) }
            }
            guard blocks.count == total else { throw TranslationError.incompleteLayout }
            return TranslationOutput(text: blocks.map(\.text).joined(separator: "\n\n"),
                                     warning: Self.mergedWarning(outputs), blocks: blocks)
        }
        let plan = TranslationChunking.textPlan(clean)
        guard plan.pieces.count > 1 else { return nil }
        let collector = onPartial.map { PartialTextCollector(count: plan.pieces.count, separators: plan.separators, emit: $0) }
        let outputs = try await TranslationChunking.run(count: plan.pieces.count) { index in
            let partial: PartialHandler? = collector.map { collector in { @Sendable text in collector.update(index, text) } }
            return try await self.translateOnce(plan.pieces[index], layout: nil, request: request,
                                                imageJPEG: nil, imageDetails: [], onPartial: partial)
        }
        var text = outputs[0].text
        for index in 1..<outputs.count { text += plan.separators[index - 1] + outputs[index].text }
        return TranslationOutput(text: text, warning: Self.mergedWarning(outputs))
    }

    private static func mergedWarning(_ outputs: [TranslationOutput]) -> String? {
        var seen: [String] = []
        for warning in outputs.compactMap(\.warning) where !seen.contains(warning) { seen.append(warning) }
        return seen.isEmpty ? nil : seen.joined(separator: "\n")
    }

    /// One HTTP request. Language validation happens once, on the merged text.
    private func translateOnce(_ clean: String, layout: ProfessionalLayout?, request options: Request,
                               imageJPEG: Data?, imageDetails: [Data], onPartial: PartialHandler?) async throws -> TranslationOutput {
        try Task.checkCancellation()
        let settings = options.settings
        var input = clean
        var instructions = try imageJPEG == nil ? TextPreparation.instructions(settings: settings)
            : TextPreparation.imageInstructions(settings: settings)
        if options.fromImageText && settings.mode != .quick {
            instructions += "\n输入来自本机截图 OCR。完整翻译每个块到最后一项，不删除内容块或独立数字。保持标题、说明、选项、价格和数量的所属关系；不确定或截断的文字不能靠常识补全。日英重复仍须遵守每块数字完整的约束。不要概括成摘要。"
        }
        if let layout {
            input = try layout.requestText()
            instructions += "\n" + ProfessionalLayout.instructions
        }
        let config = settings.configuration
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.missingModel
        }
        var request = try authorizedRequest(configuration: config, apiKey: options.apiKey, timeout: options.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if imageJPEG != nil, Self.isTextOnly(model, provider: settings.provider) {
            throw TranslationError.visionUnsupported
        }
        var body: [String: Any] = ["model": model, "stream": onPartial != nil]
        let images = imageJPEG.map { [$0] + imageDetails } ?? []
        let imageURLs = images.map { "data:image/jpeg;base64," + $0.base64EncodedString() }
        func detailLabel(_ index: Int, type: String) -> [String: Any] {
            ["type": type, "text": "局部细节图\(index)：与第1张全图为同一张图片，仅供核对小字，不是新增场景。"]
        }
        if config.style == .anthropicMessages {
            body["system"] = instructions
            body["max_tokens"] = 8192
            if !images.isEmpty {
                var content: [[String: Any]] = []
                for (index, image) in images.enumerated() {
                    if index > 0 { content.append(detailLabel(index, type: "text")) }
                    content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()]])
                }
                content.append(["type": "text", "text": input])
                body["messages"] = [["role": "user", "content": content]]
            } else { body["messages"] = [["role": "user", "content": input]] }
        } else if config.style == .responses {
            body["instructions"] = instructions
            if !imageURLs.isEmpty {
                var content: [[String: Any]] = [["type": "input_text", "text": input]]
                for (index, url) in imageURLs.enumerated() {
                    if index > 0 { content.append(detailLabel(index, type: "input_text")) }
                    content.append(["type": "input_image", "image_url": url, "detail": "high"])
                }
                body["input"] = [["role": "user", "content": content]]
            } else { body["input"] = input }
            body["store"] = false
        } else {
            var messages: [[String: Any]] = [["role": "system", "content": instructions]]
            if !imageURLs.isEmpty {
                var content: [[String: Any]] = [["type": "text", "text": input]]
                for (index, url) in imageURLs.enumerated() {
                    if index > 0 { content.append(detailLabel(index, type: "text")) }
                    content.append(["type": "image_url", "image_url": ["url": url, "detail": "high"]])
                }
                messages.append(["role": "user", "content": content])
            } else { messages.append(["role": "user", "content": input]) }
            body["messages"] = messages
        }
        Self.applyOutputLimits(to: &body, settings: settings, configuration: config, model: model)
        Self.applyReasoning(to: &body, settings: settings, configuration: config, model: model)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        var output: TranslationOutput
        if let onPartial {
            output = try await performStreaming(request, style: config.style, layoutPreview: layout != nil, onPartial: onPartial)
        } else {
            output = try Self.parseTranslation(try await perform(request), style: config.style)
        }
        if let layout {
            let blocks = try layout.restoreBlocks(output.text)
            output.blocks = blocks
            output.text = blocks.map(\.text).joined(separator: "\n\n")
        }
        return output
    }

    /// Models their provider documents as text only; an image would be refused there.
    static func isTextOnly(_ model: String, provider: AIProvider) -> Bool {
        switch provider {
        case .deepSeek: return model == "deepseek-v4-pro"
        case .zhipu: return model.lowercased() == "glm-5.3"
        default: return false
        }
    }

    /// Fields a known model needs to return a whole answer, whatever the
    /// reasoning setting. Unknown models and other interface formats get nothing.
    static func applyOutputLimits(to body: inout [String: Any], settings: AppSettings,
                                  configuration config: ProviderConfiguration, model: String) {
        guard config.style == .chatCompletions else { return }
        let id = model.lowercased()
        switch settings.provider {
        case .doubao where id.hasPrefix("doubao-seed-2-1"):
            // Without a limit the answer stops at 4K tokens.
            body["max_tokens"] = 16_000
        case .kimi where id.hasPrefix("kimi-k3"):
            // Reasoning counts toward the limit; Kimi's documentation asks for 16000 or more.
            body["max_tokens"] = 16_000
        case .minimax where id.hasPrefix("minimax-m"):
            // Keeps the model's thinking out of the translated text.
            body["reasoning_split"] = true
            if id.hasPrefix("minimax-m3") { body["max_completion_tokens"] = 32_000 }
        default:
            break
        }
    }

    /// Reasoning fields. `nil` (自动) lowers reasoning for known model families
    /// (most of all in quick mode) and otherwise sends nothing; an explicit
    /// choice is sent in the provider's own format, and an unsupported choice
    /// surfaces as the provider's error message.
    static func applyReasoning(to body: inout [String: Any], settings: AppSettings,
                               configuration config: ProviderConfiguration, model: String) {
        guard let effort = config.reasoning, settings.provider.reasoningOptions.contains(effort) else {
            applyAutomaticReasoning(to: &body, settings: settings, configuration: config, model: model)
            return
        }
        let off = effort == .off
        let level = effort.rawValue
        if settings.provider == .qwen {
            if off, config.style != .anthropicMessages { body["enable_thinking"] = false }
            return
        }
        switch config.style {
        case .responses:
            body["reasoning"] = ["effort": off ? "none" : level]
        case .chatCompletions:
            switch settings.provider {
            case .deepSeek:
                body["thinking"] = ["type": off ? "disabled" : "enabled"]
                if !off { body["reasoning_effort"] = level }
            case .gemini:
                // Gemini 2.x Flash can turn thinking off; later models only go down to minimal.
                body["reasoning_effort"] = off ? (model.hasPrefix("gemini-2") ? "none" : "minimal") : level
            case .doubao:
                body["thinking"] = ["type": off ? "disabled" : "enabled"]
                if !off { body["reasoning_effort"] = level }
            case .kimi:
                // K3 always thinks and takes low, high or max.
                body["reasoning_effort"] = threeStepEffort(effort)
            case .zhipu:
                let id = model.lowercased()
                if id.hasPrefix("glm-5.3") {
                    // Thinking cannot be turned off; these models take low, high or max.
                    body["reasoning_effort"] = threeStepEffort(effort)
                } else {
                    body["thinking"] = ["type": off ? "disabled" : "enabled"]
                    // Earlier models switch thinking on or off and have no effort level.
                    if !off, id.hasPrefix("glm-5.2") { body["reasoning_effort"] = level }
                }
            case .minimax:
                if model.lowercased().hasPrefix("minimax-m3.1") {
                    // Thinking is always on for this model; only the effort goes down.
                    body["reasoning_effort"] = off ? "low" : level
                } else {
                    // Other models think or do not, and ignore an effort level.
                    body["thinking"] = ["type": off ? "disabled" : "adaptive"]
                }
            default:
                body["reasoning_effort"] = off ? "none" : level
            }
        case .anthropicMessages:
            if settings.provider == .deepSeek {
                body["thinking"] = ["type": off ? "disabled" : "enabled"]
                if !off { body["output_config"] = ["effort": level] }
            } else {
                applyClaudeThinking(to: &body, effort: effort, model: model)
            }
        }
    }

    /// 关闭 and 低 share the lowest step on models that take only low, high and max.
    private static func threeStepEffort(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .off, .low: return "low"
        case .medium: return "high"
        case .high: return "max"
        }
    }

    private static func applyClaudeThinking(to body: inout [String: Any], effort: ReasoningEffort, model: String) {
        let id = model.lowercased()
        // Older models only understand a fixed thinking budget and do not think unless asked.
        let budgetPrefixes = ["claude-3", "claude-haiku-4", "claude-sonnet-4-5", "claude-sonnet-4-0", "claude-sonnet-4-2",
                              "claude-opus-4-0", "claude-opus-4-1", "claude-opus-4-5", "claude-opus-4-2"]
        if budgetPrefixes.contains(where: { id.hasPrefix($0) }) || id == "claude-sonnet-4" || id == "claude-opus-4" {
            let budget: Int
            switch effort {
            case .off: return
            case .low: budget = 1_024
            case .medium: budget = 4_096
            case .high: budget = 8_192
            }
            // Thinking counts toward max_tokens; keep the translation's own room.
            body["thinking"] = ["type": "enabled", "budget_tokens": budget]
            body["max_tokens"] = 8_192 + budget
            return
        }
        if effort == .off {
            if id.hasPrefix("claude-sonnet-5-5") {
                body["thinking"] = ["type": "between_tools"]
            } else if ["claude-opus-5-5", "claude-fable", "claude-mythos"].contains(where: { id.hasPrefix($0) }) {
                // Thinking cannot be turned off on these models; use the lowest effort.
                body["output_config"] = ["effort": "low"]
            } else {
                body["thinking"] = ["type": "disabled"]
            }
            return
        }
        body["thinking"] = ["type": "adaptive"]
        body["output_config"] = ["effort": effort.rawValue]
        body["max_tokens"] = 16_000
    }

    /// 自动: only documented fields for known model families; custom endpoints get nothing.
    private static func applyAutomaticReasoning(to body: inout [String: Any], settings: AppSettings,
                                                configuration config: ProviderConfiguration, model: String) {
        // DeepSeek defaults to high reasoning. Use low for a bounded translation
        // task while retaining reasoning for professional layout and vision.
        // Never add provider-specific fields to an unknown/custom endpoint.
        if settings.provider == .deepSeek, ["deepseek-flash", "deepseek-v4-pro"].contains(model) {
            if config.style == .responses {
                body["reasoning"] = ["effort": settings.preferSpeed ? "none" : "low"]
            } else {
                body["thinking"] = ["type": settings.preferSpeed ? "disabled" : "enabled"]
                if !settings.preferSpeed {
                    if config.style == .anthropicMessages { body["output_config"] = ["effort": "low"] }
                    else { body["reasoning_effort"] = "low" }
                }
            }
        }
        if settings.preferSpeed {
            if settings.provider == .openAI {
                let efforts = ["gpt-6-luna": "none", "gpt-6-sol": "none", "gpt-6.1-sol": "low", "gpt-6-astra": "low"]
                if let effort = efforts[model] {
                    if config.style == .responses { body["reasoning"] = ["effort": effort] }
                    else if config.style == .chatCompletions { body["reasoning_effort"] = effort }
                }
            }
        }
        let id = model.lowercased()
        let quick = settings.preferSpeed
        if quick, settings.provider == .claude, config.style == .anthropicMessages,
           ["claude-opus-5", "claude-sonnet-5", "claude-haiku-5", "claude-fable", "claude-mythos"].contains(where: { id.hasPrefix($0) }) {
            // The 5 series thinks adaptively by default (Sonnet 5.5 at high
            // effort). Low effort keeps a quick translation short; thinking stays
            // available, which Anthropic recommends over turning it off.
            body["output_config"] = ["effort": "low"]
        }
        // These models think at full depth unless told otherwise, which is slow
        // for a translation. Only model families whose fields are documented.
        guard config.style == .chatCompletions else { return }
        switch settings.provider {
        case .gemini where quick && id.hasPrefix("gemini-2.5-flash"):
            // 2.5 Flash and Flash-Lite can turn thinking off.
            body["reasoning_effort"] = "none"
        case .gemini where quick && id.contains("flash") && (id.hasPrefix("gemini-3") || id.hasPrefix("gemini-4")):
            // Thinking cannot be turned off on later models; minimal is their lowest level.
            body["reasoning_effort"] = "minimal"
        case .doubao where id.hasPrefix("doubao-seed-2-1"), .zhipu where id.hasPrefix("glm-5.2"):
            body["thinking"] = ["type": quick ? "disabled" : "enabled"]
            if !quick { body["reasoning_effort"] = "low" }
        case .kimi where id.hasPrefix("kimi-k3"), .zhipu where id.hasPrefix("glm-5.3"),
             .minimax where id.hasPrefix("minimax-m3.1"):
            // Thinking cannot be turned off here.
            body["reasoning_effort"] = "low"
        case .minimax where id == "minimax-m3":
            if quick { body["thinking"] = ["type": "disabled"] }
        default:
            break
        }
    }

    static func validateOutputLanguage(_ text: String, target: TargetLanguage, fromImage: Bool = false) throws {
        let scalars = text.unicodeScalars
        let han = scalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
        let kana = scalars.filter { (0x3040...0x30FF).contains($0.value) }.count
        switch target {
        case .english:
            // Catch an observed failure: English section headings with whole Chinese
            // paragraphs. Keep short names, IDs and bilingual terminology valid.
            let cjk = han + kana
            let latin = scalars.filter { (0x41...0x5A).contains($0.value) || (0x61...0x7A).contains($0.value) }.count
            let sentences = text.filter { "。！？".contains($0) }.count
            if cjk >= 80, Double(cjk) > Double(latin) * 1.5, sentences >= 2 {
                throw TranslationError.unexpectedLanguage
            }
        case .japanese:
            // Japanese prose always carries kana. A long reply with almost none and
            // several simplified-only characters is Chinese, not Japanese.
            guard !fromImage, han + kana >= 80, Double(kana) / Double(han + kana) < 0.08 else { return }
            let simplifiedOnly = Set("这们么吗还让给说时对过从个为发现经关东车门问间长无")
            if text.filter({ simplifiedOnly.contains($0) }).count >= 4 { throw TranslationError.unexpectedLanguage }
        case .simplifiedChinese:
            // Katakana names are normal in Chinese text; a quarter of kana is not.
            guard !fromImage, kana >= 60 else { return }
            if Double(kana) / Double(han + kana) >= 0.25 { throw TranslationError.unexpectedLanguage }
        }
    }

    func models(configuration: ProviderConfiguration, apiKey: String) async throws -> [String] {
        let request = try authorizedRequest(configuration: configuration, apiKey: apiKey,
                                            timeout: 15, models: true)
        let data = try await perform(request)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]] else {
            throw TranslationError.malformedResponse
        }
        let models = Array(Set(items.compactMap { $0["id"] as? String })).sorted()
        guard !models.isEmpty else { throw TranslationError.emptyResponse }
        return models
    }

    private func authorizedRequest(configuration: ProviderConfiguration, apiKey: String,
                                   timeout: TimeInterval, models: Bool = false) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw TranslationError.missingKey }
        guard !key.contains("\n"), !key.contains("\r") else { throw TranslationError.credentialUnavailable }
        var request = URLRequest(url: try Self.endpoint(configuration: configuration, models: models))
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if configuration.style == .anthropicMessages {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw TranslationError.malformedResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw ProviderErrorMessage.error(status: http.statusCode, body: data, secrets: Self.secrets(of: request))
            }
            guard data.count <= 2_000_000 else { throw TranslationError.malformedResponse }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as TranslationError { throw error }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? TranslationError.timeout : TranslationError.network
        } catch { throw TranslationError.network }
    }

    /// The credential sent with a request, so an echoed key is never shown.
    private static func secrets(of request: URLRequest) -> [String] {
        var values: [String] = []
        if let key = request.value(forHTTPHeaderField: "x-api-key") { values.append(key) }
        if let auth = request.value(forHTTPHeaderField: "Authorization") {
            values.append(auth.hasPrefix("Bearer ") ? String(auth.dropFirst(7)) : auth)
        }
        return values
    }

    private func performStreaming(_ request: URLRequest, style: APIStyle, layoutPreview: Bool,
                                  onPartial: PartialHandler) async throws -> TranslationOutput {
        #if canImport(FoundationNetworking)
        return try Self.parseTranslation(try await perform(request), style: style)
        #else
        let secrets = Self.secrets(of: request)
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw TranslationError.malformedResponse }
            guard (200..<300).contains(http.statusCode) else {
                var body = Data()
                for try await byte in bytes {
                    body.append(byte)
                    if body.count >= 65_536 { break }
                }
                throw ProviderErrorMessage.error(status: http.statusCode, body: body, secrets: secrets)
            }
            var accumulator = TranslationStreamAccumulator(style: style)
            var plainBody: [String] = []
            var isEventStream: Bool?
            var received = 0
            var lastEmit: TimeInterval = 0
            for try await line in bytes.lines {
                try Task.checkCancellation()
                received += line.utf8.count + 1
                guard received <= 2_000_000 else { throw TranslationError.malformedResponse }
                if isEventStream == nil {
                    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                    // Some compatible endpoints ignore "stream" and answer with plain JSON.
                    isEventStream = TranslationStreamAccumulator.isEventLine(line)
                }
                guard isEventStream == true else { plainBody.append(line); continue }
                guard try accumulator.consume(line: line, secrets: secrets) else { continue }
                let now = ProcessInfo.processInfo.systemUptime
                guard now - lastEmit >= 0.08 else { continue }
                let preview = layoutPreview ? StreamingPreview.blocksText(accumulator.text)
                    : accumulator.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preview.isEmpty else { continue }
                lastEmit = now
                onPartial(preview)
            }
            try Task.checkCancellation()
            if isEventStream == true { return try accumulator.finish() }
            return try Self.parseTranslation(Data(plainBody.joined(separator: "\n").utf8), style: style)
        } catch is CancellationError { throw CancellationError() }
        catch let error as TranslationError { throw error }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? TranslationError.timeout : TranslationError.network
        } catch { throw TranslationError.network }
        #endif
    }

    static func parseTranslation(_ data: Data, style: APIStyle) throws -> TranslationOutput {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.malformedResponse
        }
        var text: String
        let warning: String? = nil
        if style == .anthropicMessages {
            guard let content = root["content"] as? [[String: Any]] else { throw TranslationError.malformedResponse }
            text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if root["stop_reason"] as? String == "max_tokens" { throw TranslationError.incompleteTranslation }
            if root["stop_reason"] as? String == "refusal" { throw TranslationError.emptyResponse }
        } else if style == .chatCompletions {
            guard let choices = root["choices"] as? [[String: Any]], let first = choices.first,
                  let message = first["message"] as? [String: Any] else {
                throw TranslationError.malformedResponse
            }
            if let content = message["content"] as? String { text = content }
            else if let content = message["content"] as? [[String: Any]] {
                text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            } else { text = "" }
            if first["finish_reason"] as? String == "length" { throw TranslationError.incompleteTranslation }
        } else {
            guard let output = root["output"] as? [[String: Any]] else {
                throw TranslationError.malformedResponse
            }
            // A reasoning item may precede the output message; never assume output[0] is text.
            let parts = output.filter { $0["type"] as? String == "message" }
                .flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "output_text" }
                .compactMap { $0["text"] as? String }
            text = parts.joined(separator: "\n")
            if root["status"] as? String == "incomplete" { throw TranslationError.incompleteTranslation }
            if root["status"] as? String == "failed" { throw TranslationError.emptyResponse }
        }
        text = TranslationFormatting.normalized(text)
        guard !text.isEmpty else { throw TranslationError.emptyResponse }
        return TranslationOutput(text: text, warning: warning)
    }
}
