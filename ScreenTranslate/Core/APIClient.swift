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

    func translate(_ text: String, settings: AppSettings, apiKey: String,
                   timeout: TimeInterval = 25, imageJPEG: Data? = nil, fromImageText: Bool = false,
                   preserveBlocks: Bool = false, readingBlocks: [ReadingBlock]? = nil,
                   imageDetails: [Data] = []) async throws -> TranslationOutput {
        try Task.checkCancellation()
        guard imageDetails.isEmpty || imageJPEG != nil else { throw TranslationError.invalidImage }
        let detailBytes: Int = imageDetails.reduce(0) { total, data in total + data.count }
        let imageBytes: Int = (imageJPEG?.count ?? 0) + detailBytes
        guard imageDetails.count <= 2, imageBytes <= 8_388_608 else { throw TranslationError.imageTooLarge }
        var clean = try TextPreparation.validated(text)
        let layout = preserveBlocks && imageJPEG == nil ? ProfessionalLayout(clean, readingBlocks: readingBlocks) : nil
        var instructions = try imageJPEG == nil ? TextPreparation.instructions(settings: settings)
            : TextPreparation.imageInstructions(settings: settings)
        if fromImageText && settings.mode != .quick {
            instructions += "\n输入来自本机截图 OCR。完整翻译每个块到最后一项，不删除内容块或独立数字。保持标题、说明、选项、价格和数量的所属关系；不确定或截断的文字不能靠常识补全。日英重复仍须遵守每块数字完整的约束。不要概括成摘要。"
        }
        if let layout {
            clean = try layout.requestText()
            instructions += "\n" + ProfessionalLayout.instructions
        }
        let config = settings.configuration
        guard !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.missingModel
        }
        var request = try authorizedRequest(configuration: config, apiKey: apiKey, timeout: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if imageJPEG != nil, settings.provider == .deepSeek, model == "deepseek-v4-pro" {
            throw TranslationError.visionUnsupported
        }
        var body: [String: Any] = ["model": model, "stream": false]
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
                content.append(["type": "text", "text": clean])
                body["messages"] = [["role": "user", "content": content]]
            } else { body["messages"] = [["role": "user", "content": clean]] }
        } else if config.style == .responses {
            body["instructions"] = instructions
            if !imageURLs.isEmpty {
                var content: [[String: Any]] = [["type": "input_text", "text": clean]]
                for (index, url) in imageURLs.enumerated() {
                    if index > 0 { content.append(detailLabel(index, type: "input_text")) }
                    content.append(["type": "input_image", "image_url": url, "detail": "high"])
                }
                body["input"] = [["role": "user", "content": content]]
            } else { body["input"] = clean }
            body["store"] = false
        } else {
            var messages: [[String: Any]] = [["role": "system", "content": instructions]]
            if !imageURLs.isEmpty {
                var content: [[String: Any]] = [["type": "text", "text": clean]]
                for (index, url) in imageURLs.enumerated() {
                    if index > 0 { content.append(detailLabel(index, type: "text")) }
                    content.append(["type": "image_url", "image_url": ["url": url, "detail": "high"]])
                }
                messages.append(["role": "user", "content": content])
            } else { messages.append(["role": "user", "content": clean]) }
            body["messages"] = messages
        }
        if settings.preferSpeed {
            // Only send documented provider-specific parameters for known models.
            // A custom OpenAI-compatible endpoint need not implement these fields.
            if settings.provider == .deepSeek, ["deepseek-flash", "deepseek-v4-pro"].contains(model) {
                if config.style == .responses { body["reasoning"] = ["effort": "none"] }
                else { body["thinking"] = ["type": "disabled"] }
            }
            if settings.provider == .openAI {
                let efforts = ["gpt-6-luna": "none", "gpt-6-sol": "none", "gpt-6.1-sol": "low", "gpt-6-astra": "low"]
                if let effort = efforts[model] {
                    if config.style == .responses { body["reasoning"] = ["effort": effort] }
                    else if config.style == .chatCompletions { body["reasoning_effort"] = effort }
                }
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request)
        var output = try Self.parseTranslation(data, style: config.style)
        if let layout {
            output.blocks = try layout.restoreBlocks(output.text)
            output.text = output.blocks!.map(\.text).joined(separator: "\n\n")
        }
        return output
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
            guard (200..<300).contains(http.statusCode) else { throw TranslationError.http(http.statusCode) }
            guard data.count <= 2_000_000 else { throw TranslationError.malformedResponse }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as TranslationError { throw error }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? TranslationError.timeout : TranslationError.network
        } catch { throw TranslationError.network }
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
