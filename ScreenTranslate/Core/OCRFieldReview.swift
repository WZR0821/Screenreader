import Foundation

/// A known numeric label with an empty neighbouring region warrants a pixel
/// retry. It does not imply a value: blank fields remain blank unless two
/// independent scales recognise the same visible number and unit.
enum OCRFieldReview {
    static let labels: Set<String> = ["数量", "価格", "税込価格", "税抜価格", "販売価格", "通常価格", "价格", "合計", "总计",
        "重量", "送料", "在庫", "人数", "金額", "最低文字数", "quantity", "price", "total", "total paid",
        "weight", "shipping", "stock", "guests", "minimum length"]

    static func isNumericLabel(_ text: String) -> Bool {
        labels.contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func regions(in lines: [RecognizedLine]) -> [OCRTextBox] {
        lines.compactMap { label in
            guard isNumericLabel(label.text), label.x + label.width < 0.85 else { return nil }
            let centre = label.y + label.height / 2
            let sameRow: (RecognizedLine) -> Bool = {
                abs($0.y + $0.height / 2 - centre) < max($0.height, label.height) * 0.85
            }
            let start = label.x + label.width + 0.015
            let nextLabel = lines.filter { $0.x > start && sameRow($0) && isNumericLabel($0.text) }
                .map(\.x).min() ?? 0.99
            let end = nextLabel - 0.01
            let controls: Set<String> = ["+", "＋", "−", "-", "○", "◯"]
            // An already recognised value (including 'free' or 'not available')
            // is not an empty field. Do not fetch a number from an adjacent row.
            guard end - start > 0.05, !lines.contains(where: {
                $0 != label && $0.x >= start && $0.x < end && sameRow($0)
                    && !controls.contains($0.text) && !isNumericLabel($0.text)
            }) else { return nil }
            let bottom = max(0, centre - label.height * 1.2)
            let top = min(1, centre + label.height * 1.2)
            return OCRTextBox(x: start, y: bottom, width: end - start, height: top - bottom)
        }
    }

    static func agreedValue(_ first: String, _ second: String) -> String? {
        func canonical(_ text: String) -> String {
            (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
                .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        }
        let value = canonical(first)
        guard value == canonical(second), value.count <= 32,
              value.range(of: #"^[¥￥$€£]?[0-9][0-9,.]*(?:円|元|日元|g|kg|mg|個|人|枚|文字|yen|JPY|USD)?(?:[（(](?:税込|税抜|含税)[）)])?$"#,
                          options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return value
    }
}
