import Foundation

/// Reads the human-readable message from a provider's JSON error body.
/// Only structured message fields are used: a raw or non-JSON body is never
/// shown, and anything that looks like a credential is masked.
enum ProviderErrorMessage {
    static let maximumLength = 200

    static func extract(_ data: Data, secrets: [String] = []) -> String? {
        guard !data.isEmpty, data.count <= 65_536,
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        // Gemini's OpenAI-compatible endpoint may wrap the error in an array.
        let root = (json as? [Any])?.first ?? json
        guard let object = root as? [String: Any] else { return nil }
        var message: String?
        if let error = object["error"] as? [String: Any] {
            message = error["message"] as? String ?? error["msg"] as? String
        } else if let error = object["error"] as? String {
            message = error
        }
        if message == nil {
            message = object["message"] as? String ?? object["detail"] as? String ?? object["msg"] as? String
        }
        guard let message else { return nil }
        return sanitized(message, secrets: secrets)
    }

    static func sanitized(_ message: String, secrets: [String] = []) -> String? {
        var text = message
        for secret in secrets where secret.count >= 8 {
            text = text.replacingOccurrences(of: secret, with: "••••")
        }
        // Common key and token shapes, including partially masked echoes.
        let patterns = [#"(?i)bearer\s+\S+"#, #"sk-[A-Za-z0-9*_\-]{6,}"#, #"AIza[0-9A-Za-z_\-]{10,}"#,
                        #"(?i)(api[_-]?key|token|secret)(["'\s:=]+)[^\s,"'}]{6,}"#]
        for pattern in patterns {
            let template = pattern.contains("(api") ? "$1$2••••" : "••••"
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        text = String(text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) })
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.count > maximumLength { text = String(text.prefix(maximumLength)) + "…" }
        return text
    }

    static func error(status: Int, body: Data, secrets: [String]) -> TranslationError {
        if let detail = extract(body, secrets: secrets) { return .httpDetail(status, detail) }
        return .http(status)
    }
}
