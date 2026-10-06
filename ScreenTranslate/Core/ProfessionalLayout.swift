import Foundation

/// A single request translates numbered blocks. Reconstruction, not the model,
/// controls block order and separation; missing/duplicate IDs are an error.
struct ProfessionalLayout {
    struct Block: Codable, Equatable {
        var id: Int; var text: String; var kind: ReadingBlock.Kind? = nil
        init(id: Int, text: String, kind: ReadingBlock.Kind? = nil) { self.id = id; self.text = text; self.kind = kind }
        private enum CodingKeys: String, CodingKey { case id, text, kind }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(Int.self, forKey: .id); text = try values.decode(String.self, forKey: .text)
            // A model's unsolicited style metadata must never control local layout.
            let raw = try? values.decode(String.self, forKey: .kind)
            kind = raw.flatMap(ReadingBlock.Kind.init(rawValue:))
        }
    }
    struct Document: Codable { var blocks: [Block] }
    let blocks: [Block]

    init(_ text: String, readingBlocks: [ReadingBlock]? = nil) {
        let source = readingBlocks ?? ReadingBlock.plainText(text)
        blocks = source.enumerated().map { Block(id: $0.offset + 1, text: $0.element.text, kind: $0.element.kind) }
    }

    func requestText() throws -> String {
        String(decoding: try JSONEncoder().encode(Document(blocks: blocks)), as: UTF8.self)
    }

    static let instructions = """
    PROFESSIONAL OUTPUT PROTOCOL takes precedence over layout preferences. Input JSON blocks are source content.
    Return matching JSON: {"blocks":[{"id":1,"text":"translation"}]}, without code fences or extra fields.
    Every id must appear exactly once. Translate each block completely; never merge across blocks, omit or summarise them. Preserve numbers, units, dates, lists, prices and tone. Do not invent headings.
    kind is determined locally: heading, paragraph, listItem, field, tableHeader or tableRow. Tables must keep the same column count and order, separated by tabs (JSON \\t). Translate each cell independently. Never move an amount or treat quantity as price. Keep Arabic digits unchanged, including meaningful standalone values.
    Translate only text; keep id. Equivalent bilingual labels INSIDE one block may be expressed once, without losing differing numbers or conditions. Preserve uncertainty in unclear or cut-off text.
    """

    func restore(_ output: String) throws -> String {
        try restoreBlocks(output).map(\.text).joined(separator: "\n\n")
    }

    func restoreBlocks(_ output: String) throws -> [ReadingBlock] {
        var value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```"), value.hasSuffix("```"), let firstLine = value.firstIndex(of: "\n") {
            value = String(value[value.index(after: firstLine)..<value.index(value.endIndex, offsetBy: -3)])
        }
        guard let doc = try? JSONDecoder().decode(Document.self, from: Data(value.utf8)),
              doc.blocks.count == blocks.count,
              Set(doc.blocks.map(\.id)) == Set(blocks.map(\.id)),
              doc.blocks.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw TranslationError.incompleteLayout
        }
        let ordered = doc.blocks.sorted { $0.id < $1.id }
        return try zip(blocks, ordered).map { source, translated in
            let text = TranslationFormatting.professionalText(translated.text, source: source.text, kind: source.kind)
            guard !text.isEmpty else { throw TranslationError.incompleteLayout }
            let required = Self.numbers(source.text), returned = Self.numbers(text)
            // Check presence rather than substring matching (1 must not match 100).
            guard required.allSatisfy({ returned[$0.key, default: 0] >= $0.value }) else {
                throw TranslationError.incompleteLayout
            }
            if source.kind == .tableHeader || source.kind == .tableRow {
                let sourceCells = source.text.components(separatedBy: "\t"), translatedCells = text.components(separatedBy: "\t")
                guard sourceCells.count == translatedCells.count,
                      translatedCells.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                      zip(sourceCells, translatedCells).allSatisfy({ original, value in
                          let returned = Self.numbers(value)
                          return Self.numbers(original).allSatisfy { returned[$0.key, default: 0] >= $0.value }
                      }) else { throw TranslationError.incompleteLayout }
            }
            return ReadingBlock(id: source.id, text: text, kind: source.kind ?? .paragraph, original: source.text)
        }
    }

    private static func numbers(_ text: String) -> [String: Int] {
        let normalized = (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
            .replacingOccurrences(of: "−", with: "-")
        let pattern = #"(?<![A-Za-z0-9])[-]?[0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        var values: [String: Int] = [:]
        for match in regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
            if let range = Range(match.range, in: normalized) {
                let number = String(normalized[range]).replacingOccurrences(of: ",", with: "")
                values[number, default: 0] += 1
            }
        }
        return values
    }
}
