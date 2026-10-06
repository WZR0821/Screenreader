import Foundation

enum OCRDateReview {
    /// A year-like long number in an explicit Japanese deadline phrase is a
    /// candidate for visual re-reading, never a reason to rewrite its digits.
    static func range(in text: String) -> Range<String.Index>? {
        text.range(of: #"(?<![0-9])20[0-9]{6,8}(?=\s*(?:まで|締切|期限))"#, options: .regularExpression)
    }

    static func replacement(original: String, first: String, second: String) -> String? {
        guard let range = range(in: original), let a = date(in: first), let b = date(in: second),
              a == b, a.hasPrefix(String(original[range].prefix(4))) else { return nil }
        var text = original; text.replaceSubrange(range, with: a); return text
    }

    private static func date(in text: String) -> String? {
        let normalized = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let pattern = #"(?<![0-9])20[0-9]{2}\s*/\s*[0-9]{1,2}\s*/\s*[0-9]{1,2}(?![0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              regex.numberOfMatches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) == 1,
              let range = normalized.range(of: pattern, options: .regularExpression) else { return nil }
        let value = normalized[range].filter { !$0.isWhitespace }
        let parts = value.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        // Preserve the separators and zero padding actually read from pixels.
        return String(value)
    }
}
