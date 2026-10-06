import Foundation

/// Currency glyphs are reviewed from pixels, never fixed by deleting digits.
/// A changed amount requires a malformed group, nearby price context and two
/// matching high-confidence readings that include an explicit currency glyph.
enum OCRCurrencyReview {
    static func range(in text: String) -> Range<String.Index>? {
        text.range(of: #"[·•・.*]\s*[0-9][0-9,，.．]*|(?<![A-Za-z0-9])[0-9]{1,3}[,，][0-9]{4,5}(?![0-9])"#, options: .regularExpression)
    }
    static func needsReview(_ line: RecognizedLine, in lines: [RecognizedLine]) -> Bool {
        guard let range = range(in: line.text) else { return false }
        if "·•・.*".contains(line.text[range].first!) { return true }
        let priceWords = #"価格|价|price|amount|total|[¥￥]|円"#
        return line.text.range(of: priceWords, options: [.regularExpression, .caseInsensitive]) != nil
            || lines.contains { other in
                other.text.range(of: priceWords, options: [.regularExpression, .caseInsensitive]) != nil
                    && other.x < line.x
                    && abs(other.y + other.height / 2 - line.y - line.height / 2) < max(other.height, line.height) * 1.1
            }
    }
    static func replacement(original: String, first: String, second: String) -> String? {
        func clean(_ text: String) -> String {
            (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
                .replacingOccurrences(of: "￥", with: "¥")
                .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        }
        let value = clean(first)
        guard value == clean(second), let range = range(in: original),
              value.range(of: #"^(?:[¥$€£][0-9]+(?:,[0-9]{3})*|[0-9]+(?:,[0-9]{3})*円)$"#, options: .regularExpression) != nil else { return nil }
        let before = clean(String(original[range]))
        let digits: (String) -> String = { String($0.filter(\.isNumber)) }
        if "·•・.*".contains(before.first!) {
            guard digits(before) == digits(value) else { return nil }
        } else {
            // Only yen can explain the observed numeric-looking suffix. The
            // amount must match the original prefix, not an arbitrary new price.
            guard value.contains("¥") || value.hasSuffix("円") else { return nil }
            let amount = value.replacingOccurrences(of: "¥", with: "").replacingOccurrences(of: "円", with: "")
            guard digits(before) == digits(amount) || before.hasPrefix(amount) else { return nil }
        }
        var result = original
        result.replaceSubrange(range, with: value)
        return result == original ? nil : result
    }
}
