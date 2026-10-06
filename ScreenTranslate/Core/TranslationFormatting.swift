import Foundation

enum TranslationFormatting {
    /// Keep punctuation, numbers and intentional single line breaks. Normalize only
    /// presentation whitespace; never use the shortened preview as the saved result.
    static func normalized(_ text: String) -> String {
        String(text.unicodeScalars.filter { !((0...31).contains($0.value) || (127...159).contains($0.value)) || [9, 10, 13, 133].contains($0.value) })
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0085}", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Professional output already has local block styling. Remove only a
    /// redundant whole-block Markdown wrapper that was absent from the source.
    /// Inline asterisks, hashtags, maths and source punctuation stay untouched.
    static func professionalText(_ output: String, source: String, kind: ReadingBlock.Kind?) -> String {
        var value = normalized(output)
        let original = normalized(source)
        if kind == .heading, !original.hasPrefix("#") {
            value = value.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        }
        if !original.contains("**"), value.count > 4, value.hasPrefix("**"), value.hasSuffix("**"),
           !value.dropFirst(2).dropLast(2).contains("**") {
            value = String(value.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    static func preview(_ text: String, limit: Int = 180) -> (text: String, shortened: Bool) {
        let clean = normalized(text)
        // A bounded excerpt prevents a huge static system snippet. The full string
        // is still returned to Shortcuts and rendered without line limits in the app.
        let lines = clean.components(separatedBy: "\n")
        let candidate = lines.prefix(6).joined(separator: "\n")
        let excerpt = String(candidate.prefix(max(1, limit))).trimmingCharacters(in: .whitespacesAndNewlines)
        return (excerpt, excerpt != clean)
    }
}
