import Foundation

/// Types and reading order come from local geometry, never from model markup.
struct ReadingBlock: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case heading, paragraph, listItem, field, tableHeader, tableRow }
    var id: Int
    var text: String
    var kind: Kind = .paragraph
    var original: String? = nil

    var tableCells: [String]? {
        guard kind == .tableHeader || kind == .tableRow else { return nil }
        return text.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func plainText(_ text: String) -> [ReadingBlock] {
        var blocks: [ReadingBlock] = []
        var paragraph: [String] = []
        func append(_ text: String, kind: Kind) {
            blocks.append(.init(id: blocks.count + 1, text: text, kind: kind))
        }
        func flush() {
            if !paragraph.isEmpty { append(paragraph.joined(separator: "\n"), kind: .paragraph); paragraph.removeAll() }
        }
        // A list may sit between prose without blank lines. Do not put the
        // entire paragraph inside one bullet, or turn a decimal into a list.
        for row in TranslationFormatting.normalized(text).components(separatedBy: "\n") {
            if row.isEmpty { flush() }
            else if isListRow(row) { flush(); append(row, kind: .listItem) }
            else { paragraph.append(row) }
        }
        flush()
        return blocks
    }

    static func isListRow(_ text: String) -> Bool {
        hasSemanticMarker(text) || text.range(of: #"^\s*(?:[•●・▪]\s*|[-*]\s+|[0-9０-９]{1,3}[.)、．](?![0-9０-９])\s*)\S"#, options: .regularExpression) != nil
    }

    var listText: String {
        // Keep numbered lists (the number may matter); remove only a duplicate bullet.
        text.replacingOccurrences(of: #"^\s*(?:[•●・▪]|[-*]\s+)\s*"#, with: "", options: .regularExpression)
    }

    var isNumberedList: Bool {
        text.range(of: #"^\s*[0-9０-９]{1,3}[.)、．](?![0-9０-９])\s*\S"#, options: .regularExpression) != nil
    }

    /// Semantic markers (warning / checked / unchecked) replace the ordinary
    /// bullet in both readers; retain the marker itself and never duplicate it.
    var hasVisibleListMarker: Bool {
        isNumberedList || Self.hasSemanticMarker(text)
    }

    private static func hasSemanticMarker(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Read a complete grapheme so a variation selector is never treated as
        // a second character. This works for literal, decoded and OCR strings.
        guard let first = value.first, let scalar = first.unicodeScalars.first,
              [UInt32(0x2705), 0x2611, 0x2610, 0x26A0].contains(scalar.value) else { return false }
        return !value.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var fieldParts: (label: String, value: String)? {
        guard kind == .field else { return nil }
        let labels = OCRFieldReview.labels.union(["日付", "入場時間", "予約番号", "date", "entry time", "reference",
            "金额", "含税价", "税前价", "优惠价", "原价", "运费", "库存", "人数", "日期", "入场时间", "预订编号",
            "订单编号", "最低字数", "总付款", "已付总额", "总金额"])
        for separator in ["：", ":", "\n"] {
            let parts = text.components(separatedBy: separator)
            if parts.count >= 2 {
                let label = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
                if labels.contains(label.lowercased()), !value.isEmpty { return (label, value) }
            }
        }
        // Only an unambiguous short item + one currency amount is split into
        // columns. Discount explanations and body sentences stay intact.
        guard let first = text.first, !first.isNumber, !"¥￥$€£".contains(first) else { return nil }
        let pattern = #"^([^\n。！？!?]{1,50}?)\s*((?:[¥￥$€£]\s*[0-9][0-9,.，．]*|[0-9][0-9,.，．]*\s*(?:日元|円|元|yen|JPY|USD))(?:起|から|〜)?(?:\s*[（(][^\n]{1,20}[）)])?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let label = Range(match.range(at: 1), in: text), let value = Range(match.range(at: 2), in: text) else { return nil }
        let cleanLabel = String(text[label]).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":：")))
        guard !cleanLabel.isEmpty else { return nil }
        return (cleanLabel, String(text[value]))
    }
}
