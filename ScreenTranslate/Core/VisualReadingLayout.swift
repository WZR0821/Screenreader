import Foundation

enum VisualReadingLayout {
    struct Headings {
        var text: String; var scene: String; var uncertain: String
    }
    static func headings(for target: TargetLanguage) -> Headings {
        switch target {
        case .simplifiedChinese: return .init(text: "文字大意", scene: "画面大意", uncertain: "部分文字无法辨认")
        case .english: return .init(text: "Text meaning", scene: "Scene", uncertain: "Some text is unreadable")
        case .japanese: return .init(text: "文字の意味", scene: "画像の内容", uncertain: "一部の文字は判読できません")
        }
    }

    /// Recognize only the explicitly requested section labels, never arbitrary
    /// model markup. Preserve every other line even if it ignores the format.
    static func blocks(_ text: String, target: TargetLanguage) -> [ReadingBlock] {
        let labels = headings(for: target)
        var result: [ReadingBlock] = [], paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty {
                result += ReadingBlock.plainText(paragraph.joined(separator: "\n")); paragraph.removeAll()
            }
        }
        for line in TranslationFormatting.normalized(text).components(separatedBy: "\n") {
            if line.isEmpty { flush(); continue }
            var label: String?, rest = ""
            for heading in [labels.text, labels.scene] {
                if line == heading { label = heading; break }
                for separator in ["：", ":"] where line.hasPrefix(heading + separator) {
                    label = heading; rest = String(line.dropFirst(heading.count + separator.count)).trimmingCharacters(in: .whitespaces)
                }
            }
            if let label {
                flush(); result.append(.init(id: 0, text: label, kind: .heading))
                if !rest.isEmpty { paragraph.append(rest) }
            } else if ReadingBlock.isListRow(line) {
                flush(); result.append(.init(id: 0, text: line, kind: .listItem))
            } else { paragraph.append(line) }
        }
        flush()
        return result.enumerated().map { index, block in
            var block = block; block.id = index + 1; return block
        }
    }
}
