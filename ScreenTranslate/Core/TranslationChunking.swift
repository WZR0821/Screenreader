import Foundation

/// Splits long text into a few requests that run concurrently, so a long
/// screenshot is neither cut off by the output limit nor stuck on one slow
/// request. Short text (the common case) is always sent in one request.
enum TranslationChunking {
    /// Only text longer than this is split.
    static let threshold = 4_000
    /// Upper bound for one request's source text.
    static let targetSize = 3_000
    static let maximumConcurrentRequests = 3

    /// Groups reading blocks in order. A block is never split: the layout
    /// protocol must return it whole, with its numbers.
    static func blockGroups(_ blocks: [ReadingBlock], limit: Int = targetSize) -> [[ReadingBlock]] {
        var groups: [[ReadingBlock]] = []
        var current: [ReadingBlock] = []
        var size = 0
        for block in blocks {
            let length = block.text.count + 2
            if !current.isEmpty && size + length > limit { groups.append(current); current = []; size = 0 }
            current.append(block); size += length
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    struct TextPlan: Equatable {
        var pieces: [String]
        /// separators[i] joins pieces[i] and pieces[i + 1].
        var separators: [String]
    }

    /// Splits at paragraph breaks first, then line breaks, then sentence ends.
    static func textPlan(_ text: String, limit: Int = targetSize) -> TextPlan {
        // Segments carry the separator that preceded them in the source.
        var segments: [(text: String, before: String)] = []
        let paragraphs = text.components(separatedBy: "\n\n")
        for (pIndex, paragraph) in paragraphs.enumerated() {
            let paragraphBefore = pIndex == 0 ? "" : "\n\n"
            guard paragraph.count > limit else { segments.append((paragraph, paragraphBefore)); continue }
            for (lIndex, line) in paragraph.components(separatedBy: "\n").enumerated() {
                let lineBefore = lIndex == 0 ? paragraphBefore : "\n"
                guard line.count > limit else { segments.append((line, lineBefore)); continue }
                for (sIndex, piece) in sentencePieces(line, limit: limit).enumerated() {
                    segments.append((piece.text, sIndex == 0 ? lineBefore : piece.before))
                }
            }
        }
        var pieces: [String] = []
        var separators: [String] = []
        var current = ""
        for segment in segments {
            if !current.isEmpty && current.count + segment.before.count + segment.text.count > limit {
                pieces.append(current); separators.append(segment.before); current = segment.text
            } else {
                current += (current.isEmpty ? "" : segment.before) + segment.text
            }
        }
        if !current.isEmpty || pieces.isEmpty { pieces.append(current) }
        // Drop empty pieces created by runs of blank lines.
        var cleanPieces: [String] = []
        var cleanSeparators: [String] = []
        for (index, piece) in pieces.enumerated() {
            if piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if !cleanPieces.isEmpty { cleanSeparators.append(index > 0 ? separators[index - 1] : "\n\n") }
            cleanPieces.append(piece)
        }
        return TextPlan(pieces: cleanPieces.isEmpty ? [text] : cleanPieces, separators: cleanSeparators)
    }

    private static func sentencePieces(_ line: String, limit: Int) -> [(text: String, before: String)] {
        var result: [(String, String)] = []
        var current = ""
        var pendingBefore = ""
        var afterLatinEnd = false
        let enders: Set<Character> = ["。", "！", "？", "!", "?", ".", "；", ";"]
        for character in line {
            if afterLatinEnd {
                afterLatinEnd = false
                // The space after a Latin sentence becomes the separator, so the
                // pieces rejoin exactly; "1.5" cut after "1." gets none.
                if character == " " { pendingBefore = " "; continue }
            }
            current.append(character)
            let atSentenceEnd = enders.contains(character) && current.count >= limit / 2
            if atSentenceEnd || current.count >= limit {
                result.append((current, pendingBefore))
                pendingBefore = ""
                afterLatinEnd = atSentenceEnd && character.isASCII
                current = ""
            }
        }
        if !current.isEmpty { result.append((current, pendingBefore)) }
        return result.map { (text: $0.0, before: $0.1) }
    }

    /// Runs `operation` for every index with bounded concurrency; results keep order.
    static func run<T: Sendable>(count: Int, limit: Int = maximumConcurrentRequests,
                                 _ operation: @escaping @Sendable (Int) async throws -> T) async throws -> [T] {
        try await withThrowingTaskGroup(of: (Int, T).self) { group in
            var results = [T?](repeating: nil, count: count)
            var next = 0
            while next < min(limit, count) {
                let index = next
                group.addTask { (index, try await operation(index)) }
                next += 1
            }
            while let (index, value) = try await group.next() {
                results[index] = value
                if next < count {
                    let upcoming = next
                    group.addTask { (upcoming, try await operation(upcoming)) }
                    next += 1
                }
            }
            return results.map { $0! }
        }
    }
}
