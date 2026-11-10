import Foundation

/// Keep local translation cells attached to their source geometry, even when
/// Apple's batch responses arrive out of order or contain paragraph breaks.
struct LocalImageTranslationPlan {
    let blocks: [ReadingBlock]
    let requests: [LocalTranslationPlan.Request]
    private let cellIDs: [[Int?]]

    init(_ blocks: [ReadingBlock]) {
        self.blocks = blocks
        var requests: [LocalTranslationPlan.Request] = [], ids: [[Int?]] = []
        var existing: [String: Int] = [:]
        for block in blocks {
            let cells = block.tableCells ?? [block.text]
            ids.append(cells.map { text in
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                if let id = existing[text] { return id }
                let id = requests.count
                requests.append(.init(index: id, text: text)); existing[text] = id
                return id
            })
        }
        self.requests = requests; cellIDs = ids
    }

    func restored(_ responses: [Int: String]) throws -> [ReadingBlock] {
        try blocks.enumerated().map { index, source in
            let cells = try cellIDs[index].map { id -> String in
                guard let id else { return "" }
                guard let response = responses[id], !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TranslationError.incompleteSystemTranslation
                }
                // A translated cell cannot create an additional table column.
                return TranslationFormatting.normalized(response).replacingOccurrences(of: "\t", with: " ")
            }
            var block = source
            block.original = source.text; block.text = cells.joined(separator: "\t")
            return block
        }
    }
}
