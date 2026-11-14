import Foundation

/// Collects text from a Server-Sent Events reply for the three supported API
/// styles. Each `data:` line holds one complete JSON event for all of them.
/// The streamed text is only a preview: the final result goes through the
/// same checks as a non-streamed reply.
struct TranslationStreamAccumulator {
    let style: APIStyle
    private(set) var text = ""
    private var incomplete = false
    private var refused = false
    private var failed = false

    init(style: APIStyle) { self.style = style }

    static func isEventLine(_ line: String) -> Bool {
        line.hasPrefix("data:") || line.hasPrefix("event:") || line.hasPrefix(":") || line.hasPrefix("id:") || line.hasPrefix("retry:")
    }

    /// Returns true when the visible text changed.
    mutating func consume(line raw: String, secrets: [String] = []) throws -> Bool {
        let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        guard line.hasPrefix("data:") else { return false }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return false }
        guard let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { return false }
        if event["error"] != nil || event["type"] as? String == "error" {
            let detail = ProviderErrorMessage.extract(Data(payload.utf8), secrets: secrets) ?? "未知错误"
            throw TranslationError.streamFailure(detail)
        }
        let before = text.count
        switch style {
        case .anthropicMessages:
            switch event["type"] as? String {
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                   let value = delta["text"] as? String { text += value }
            case "message_delta":
                let reason = (event["delta"] as? [String: Any])?["stop_reason"] as? String
                if reason == "max_tokens" { incomplete = true }
                if reason == "refusal" { refused = true }
            default: break
            }
        case .chatCompletions:
            guard let choice = (event["choices"] as? [[String: Any]])?.first else { break }
            if let delta = choice["delta"] as? [String: Any] {
                // Reasoning deltas (e.g. reasoning_content) are never shown.
                if let value = delta["content"] as? String { text += value }
                else if let parts = delta["content"] as? [[String: Any]] {
                    text += parts.compactMap { $0["text"] as? String }.joined()
                }
            }
            if choice["finish_reason"] as? String == "length" { incomplete = true }
        case .responses:
            switch event["type"] as? String {
            case "response.output_text.delta":
                if let value = event["delta"] as? String { text += value }
            case "response.incomplete": incomplete = true
            case "response.failed":
                if let error = (event["response"] as? [String: Any])?["error"] as? [String: Any],
                   let message = error["message"] as? String,
                   let detail = ProviderErrorMessage.sanitized(message, secrets: secrets) {
                    throw TranslationError.streamFailure(detail)
                }
                failed = true
            default: break
            }
        }
        return text.count != before
    }

    func finish() throws -> TranslationOutput {
        if incomplete { throw TranslationError.incompleteTranslation }
        if refused || failed { throw TranslationError.emptyResponse }
        let clean = TranslationFormatting.normalized(text)
        guard !clean.isEmpty else { throw TranslationError.emptyResponse }
        return TranslationOutput(text: clean, warning: nil)
    }
}

enum StreamingPreview {
    /// Extracts readable text from a partial `{"blocks":[{"id":1,"text":"…"}]}`
    /// reply, so the reading page never shows raw JSON while it streams.
    static func blocksText(_ partial: String) -> String {
        let scalars = Array(partial.unicodeScalars)
        let key = Array("\"text\"".unicodeScalars)
        var results: [String] = []
        var index = 0
        func skipSpace() { while index < scalars.count, [" ", "\n", "\r", "\t"].contains(scalars[index]) { index += 1 } }
        func hex(_ start: Int) -> UInt32? {
            guard start + 4 <= scalars.count else { return nil }
            var view = String.UnicodeScalarView(); view.append(contentsOf: scalars[start..<start + 4])
            return UInt32(String(view), radix: 16)
        }
        outer: while index < scalars.count {
            var found = -1
            var probe = index
            search: while probe + key.count <= scalars.count {
                for offset in 0..<key.count where scalars[probe + offset] != key[offset] { probe += 1; continue search }
                found = probe; break
            }
            guard found >= 0 else { break }
            index = found + key.count
            skipSpace()
            guard index < scalars.count, scalars[index] == ":" else { continue }
            index += 1; skipSpace()
            guard index < scalars.count, scalars[index] == "\"" else { continue }
            index += 1
            var value = String.UnicodeScalarView()
            while index < scalars.count {
                let current = scalars[index]
                if current == "\"" { index += 1; break }
                guard current == "\\" else { value.append(current); index += 1; continue }
                guard index + 1 < scalars.count else { results.append(String(value)); break outer }
                switch scalars[index + 1] {
                case "n": value.append("\n"); index += 2
                case "t": value.append("\t"); index += 2
                case "r", "b", "f": index += 2
                case "u":
                    guard let code = hex(index + 2) else { results.append(String(value)); break outer }
                    index += 6
                    if (0xD800...0xDBFF).contains(code) {
                        guard index + 1 < scalars.count, scalars[index] == "\\", scalars[index + 1] == "u",
                              let low = hex(index + 2) else { results.append(String(value)); break outer }
                        index += 6
                        let combined = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        if let scalar = Unicode.Scalar(combined) { value.append(scalar) }
                    } else if let scalar = Unicode.Scalar(code) { value.append(scalar) }
                default: value.append(scalars[index + 1]); index += 2
                }
            }
            results.append(String(value))
        }
        return results.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

/// Thread-safe holder for the latest partial text of each chunk.
final class PartialTextCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var parts: [String]
    private let separators: [String]
    private let emit: @Sendable (String) -> Void

    init(count: Int, separators: [String], emit: @escaping @Sendable (String) -> Void) {
        parts = Array(repeating: "", count: count)
        self.separators = separators
        self.emit = emit
    }

    func update(_ index: Int, _ text: String) {
        lock.lock()
        parts[index] = text
        var joined = ""
        for (offset, part) in parts.enumerated() where !part.isEmpty {
            if !joined.isEmpty {
                // A piece still waiting for its first words shows as a paragraph break.
                let adjacent = offset > 0 && offset - 1 < separators.count && !parts[offset - 1].isEmpty
                joined += adjacent ? separators[offset - 1] : "\n\n"
            }
            joined += part
        }
        lock.unlock()
        emit(joined)
    }
}
