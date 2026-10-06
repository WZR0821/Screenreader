import Foundation

/// Review recogniser/script failures using two readings of the same pixels.
/// Confidence alone is insufficient: Vision can give a Latin interpretation of
/// Japanese lettering a confidence of 1. No correction comes from a word list.
enum OCRScriptReview {
    static func needsReview(_ text: String) -> Bool {
        if text.range(of: #"^\s*[·•・.*]\s*[0-9][0-9,，.．]*\s*$"#, options: .regularExpression) != nil { return true }
        guard let slash = text.lastIndex(of: "/") else { return false }
        let prefix = text[..<slash], suffix = text[text.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        return prefix.contains(where: \.isLetter) && (3...24).contains(suffix.count)
            && suffix.contains(where: \.isNumber) && suffix.filter(\.isLetter).count <= 1
            && suffix.filter { !$0.isNumber && !$0.isWhitespace }.count >= 2
    }

    static func replacement(original: String, first: String, second: String) -> String? {
        func clean(_ value: String) -> String {
            (value.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? value)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let value = clean(first)
        guard needsReview(original), value == clean(second), value != clean(original) else { return nil }
        if original.range(of: #"^\s*[·•・.*]\s*[0-9][0-9,，.．]*\s*$"#, options: .regularExpression) != nil {
            guard value.range(of: #"^[¥￥$€£]\s*[0-9][0-9,.]*$"#, options: .regularExpression) != nil else { return nil }
            let digits: (String) -> String = { String($0.filter(\.isNumber)) }
            return digits(original) == digits(value) ? value : nil
        }
        guard let before = original.lastIndex(of: "/"), let after = value.lastIndex(of: "/"),
              clean(String(original[..<before])) == clean(String(value[..<after])) else { return nil }
        let suffix = String(value[value.index(after: after)...])
        let japanese = suffix.unicodeScalars.filter { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
        guard japanese.count >= 2 else { return nil }
        return value
    }
}
