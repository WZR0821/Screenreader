import Foundation

enum OCRRefinementPolicy {
    static func needsReview(_ line: RecognizedLine, imageHeight: Int) -> Bool {
        let meaningful = line.text.rangeOfCharacter(from: .alphanumerics) != nil
        return meaningful && (line.confidence < 0.7 || line.height * Double(imageHeight) < 18 || OCRDateReview.range(in: line.text) != nil)
    }

    static func accepts(original: RecognizedLine, replacement: String, confidence: Float) -> Bool {
        let text = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains("\n"), confidence >= 0.65,
              confidence >= original.confidence + 0.08,
              text.count <= max(12, original.text.count * 2) else { return false }
        let digits: (String) -> [String] = { value in
            let value = (value.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? value).replacingOccurrences(of: "−", with: "-")
            let regex = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])[-]?\d+(?:[,，]\d{3})*(?:[.．]\d+)?|\d+(?:[,，]\d{3})*(?:[.．]\d+)?"#)
            return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
                Range($0.range, in: value).map { String(value[$0]).replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "") }
            }
        }
        // Never silently alter prices, quantities or dates based on a single retry.
        guard digits(original.text) == digits(text) else { return false }
        return true
    }
}
