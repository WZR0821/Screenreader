import Foundation

struct TranslationReviewSelection: Identifiable {
    let id = UUID()
    let result: TranslationResult
    let blockID: Int
    var block: ReadingBlock? { result.blocks?.first { $0.id == blockID } }
}

enum TranslationReview {
    static func canReview(_ result: TranslationResult, blockID: Int) -> Bool {
        guard result.mode != .visual, result.imageMode != .visual,
              let blocks = result.blocks, !blocks.isEmpty,
              Set(blocks.map(\.id)).count == blocks.count,
              blocks.allSatisfy({ block in
                  guard let original = block.original, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                  return block.tableCells == nil || block.tableCells?.count == original.components(separatedBy: "\t").count
              }) else { return false }
        return blocks.contains { $0.id == blockID }
    }

    /// The current API is used, but the saved translation's target is retained.
    static func settings(for result: TranslationResult, using current: AppSettings) throws -> AppSettings {
        guard let target = TargetLanguage.allCases.first(where: {
            [$0.title, $0.rawValue, $0.promptName].contains(result.target)
        }) else { throw TranslationError.reviewUnavailable }
        var settings = current
        settings.mode = .professional
        settings.translationService = .api
        settings.target = target
        // The isolated paragraph needs its original language context, rather
        // than whichever source the user has selected since this translation.
        settings.source = SourceLanguage.allCases.first { $0 != .automatic && $0.title == result.sourceLanguages } ?? .automatic
        return settings
    }

    static func sourceBlock(in result: TranslationResult, blockID: Int, correctedText: String) throws -> ReadingBlock {
        guard canReview(result, blockID: blockID), let block = result.blocks?.first(where: { $0.id == blockID }) else {
            throw TranslationError.reviewUnavailable
        }
        _ = try TextPreparation.validated(correctedText)
        let text: String
        if block.tableCells != nil {
            let cells = correctedText.components(separatedBy: "\t")
            guard cells.count == block.original?.components(separatedBy: "\t").count else {
                throw TranslationError.reviewColumns
            }
            // Trimming the whole row would destroy leading/trailing empty columns.
            text = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\t")
        } else {
            text = try TextPreparation.validated(correctedText)
        }
        var source = ReadingBlock(id: block.id, text: text, kind: block.kind)
        source.copyGeometry(from: block)
        return source
    }

    static func replacing(in result: TranslationResult, blockID: Int, with replacement: ReadingBlock) throws -> TranslationResult {
        guard let original = replacement.original else { throw TranslationError.incompleteLayout }
        let source = try sourceBlock(in: result, blockID: blockID, correctedText: original)
        guard replacement.id == blockID, replacement.kind == source.kind,
              replacement.sourceBox == source.sourceBox, replacement.sourceVertical == source.sourceVertical,
              replacement.sourceCellBoxes == source.sourceCellBoxes else { throw TranslationError.incompleteLayout }
        // Keep the same column/number checks even if a caller didn't use the pipeline.
        let document = ProfessionalLayout.Document(blocks: [.init(id: 1, text: replacement.text)])
        let encoded = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        _ = try ProfessionalLayout(source.text, readingBlocks: [source]).restoreBlocks(encoded)
        var updated = result
        guard let index = updated.blocks?.firstIndex(where: { $0.id == blockID }) else {
            throw TranslationError.reviewUnavailable
        }
        // Line metrics are derived from the same OCR as the box; keep them even
        // when a caller built the replacement from the box alone.
        var stored = replacement
        stored.sourceLineHeight = source.sourceLineHeight; stored.sourceLineCount = source.sourceLineCount
        updated.blocks?[index] = stored
        updated.translated = updated.blocks!.map(\.text).joined(separator: "\n\n")
        updated.original = sourceBlocks(in: updated).map(\.text).joined(separator: "\n\n")
        // A mixed result is no longer a cache hit for the original full document.
        updated.usedCache = false
        return updated
    }

    static func sourceBlocks(in result: TranslationResult) -> [ReadingBlock] {
        (result.blocks ?? []).compactMap { block in
            guard let original = block.original else { return nil }
            var source = ReadingBlock(id: block.id, text: original, kind: block.kind)
            source.copyGeometry(from: block)
            return source
        }
    }
}
