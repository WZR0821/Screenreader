import Foundation

/// Retain paragraph separators and restore batch responses by ID, never arrival order.
struct LocalTranslationPlan {
    struct Part: Equatable { var text: String; var separator: String }
    struct Request: Equatable { var index: Int; var text: String }
    let parts: [Part]
    let requests: [Request]
    private let sourceIndices: [Int: Int]
    init(_ text: String) {
        let regex = try! NSRegularExpression(pattern: #"\n[\t ]*\n+"#)
        var cursor = text.startIndex
        var result: [Part] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            result.append(.init(text: String(text[cursor..<range.lowerBound]), separator: String(text[range])))
            cursor = range.upperBound
        }
        result.append(.init(text: String(text[cursor...]), separator: ""))
        parts = result
        var firstIndex: [String: Int] = [:], sourceIndices: [Int: Int] = [:]
        var requests: [Request] = []
        for (index, part) in result.enumerated() where !part.text.isEmpty {
            if let existing = firstIndex[part.text] { sourceIndices[index] = existing }
            else {
                firstIndex[part.text] = index; sourceIndices[index] = index
                requests.append(.init(index: index, text: part.text))
            }
        }
        self.requests = requests; self.sourceIndices = sourceIndices
    }
    var totalParts: Int { sourceIndices.count }
    func completedParts(responseIDs: Set<Int>) -> Int { sourceIndices.values.filter { responseIDs.contains($0) }.count }
    func restored(_ responses: [Int: String]) throws -> String {
        try parts.enumerated().map { index, part in
            guard !part.text.isEmpty else { return part.separator }
            guard let sourceIndex = sourceIndices[index], let translated = responses[sourceIndex],
                  !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranslationError.incompleteSystemTranslation
            }
            return translated + part.separator
        }.joined()
    }
}
