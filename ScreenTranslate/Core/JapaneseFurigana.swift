import Foundation
import CoreFoundation

/// Presentation-only readings. Original translations, copies, history and API requests stay plain text.
enum JapaneseFurigana {
    struct Annotation: Equatable, Sendable {
        let range: NSRange
        let reading: String
    }

    private final class Entry: NSObject {
        let annotations: [Annotation]
        init(_ annotations: [Annotation]) { self.annotations = annotations }
    }
    private final class Cache: @unchecked Sendable {
        let values = NSCache<NSString, Entry>()
        init() { values.countLimit = 128; values.totalCostLimit = 1_000_000 }
    }
    private static let cache = Cache()

    static func isJapanese(target: String) -> Bool {
        ["ja", "ja-jp", "japanese", "日语", "日本語"].contains(target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func annotations(for text: String) -> [Annotation] {
        guard text.contains(where: isKanji) else { return [] }
        if let cached = cache.values.object(forKey: text as NSString) { return cached.annotations }
        let source = text as NSString
        guard let tokenizer = CFStringTokenizerCreate(nil, text as CFString,
            CFRange(location: 0, length: source.length),
            kCFStringTokenizerUnitWord | kCFStringTokenizerAttributeLatinTranscription,
            Locale(identifier: "ja") as CFLocale) else { return [] }
        var result: [Annotation] = []
        var tokenBoundaries = Set<Int>()
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let token = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard token.location >= 0, token.length > 0, token.location + token.length <= source.length else { continue }
            let range = NSRange(location: token.location, length: token.length)
            tokenBoundaries.insert(range.location); tokenBoundaries.insert(NSMaxRange(range))
            let base = source.substring(with: range)
            guard base.contains(where: isKanji),
                  let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String,
                  let reading = latin.applyingTransform(.latinToHiragana, reverse: false),
                  !reading.isEmpty, reading.allSatisfy(isKana) else { continue }
            result += aligned(base: base, reading: reading).map {
                Annotation(range: NSRange(location: range.location + $0.range.location, length: $0.range.length), reading: $0.reading)
            }
        }
        // The system dictionary splits 日本語 / 日本人 into 日本 (nippon) + 語 / 人.
        // These common compounds have fixed readings independent of that token boundary.
        for (word, reading) in [("日本語", "にほんご"), ("日本人", "にほんじん")] {
            var search = NSRange(location: 0, length: source.length)
            while search.length > 0 {
                let range = source.range(of: word, range: search)
                guard range.location != NSNotFound else { break }
                // Do not replace part of a longer token such as 日本 + 人形.
                if tokenBoundaries.contains(range.location), tokenBoundaries.contains(NSMaxRange(range)) {
                    result.removeAll { NSIntersectionRange($0.range, range).length > 0 }
                    result.append(.init(range: range, reading: reading))
                }
                search = NSRange(location: NSMaxRange(range), length: source.length - NSMaxRange(range))
            }
        }
        result.sort { $0.range.location < $1.range.location }
        if source.length <= 50_000 { cache.values.setObject(Entry(result), forKey: text as NSString, cost: source.length * 4) }
        return result
    }

    /// Match the written kana as anchors, leaving ruby only over kanji (食べ物 → 食/た + べ + 物/もの).
    /// If there is more than one possible alignment, omit it rather than place a guessed reading.
    static func aligned(base: String, reading: String) -> [Annotation] {
        struct Run { var text: String; let kanji: Bool; var range: NSRange }
        var runs: [Run] = [], offset = 0
        for character in base {
            let kanji = isKanji(character), text = String(character), length = text.utf16.count
            if runs.last?.kanji == kanji {
                runs[runs.count - 1].text += text; runs[runs.count - 1].range.length += length
            } else { runs.append(.init(text: text, kanji: kanji, range: NSRange(location: offset, length: length))) }
            offset += length
        }
        guard !runs.isEmpty, runs.count <= 16, reading.count <= 100 else { return [] }
        let kana = Array(reading.precomposedStringWithCanonicalMapping)
        var solutions: [[Annotation]] = [], attempts = 0
        func visit(_ index: Int, _ position: Int, _ annotations: [Annotation]) {
            attempts += 1
            guard solutions.count < 2, attempts < 2048 else { return }
            guard index < runs.count else {
                if position == kana.count { solutions.append(annotations) }
                return
            }
            let run = runs[index]
            if !run.kanji {
                let anchor = Array((run.text.applyingTransform(.hiraganaToKatakana, reverse: true) ?? run.text).precomposedStringWithCanonicalMapping)
                guard position + anchor.count <= kana.count, Array(kana[position..<(position + anchor.count)]) == anchor else { return }
                visit(index + 1, position + anchor.count, annotations)
            } else if position < kana.count {
                let ends = index == runs.count - 1 ? [kana.count] : Array((position + 1)...kana.count)
                for end in ends {
                    visit(index + 1, end, annotations + [.init(range: run.range, reading: String(kana[position..<end]))])
                    if solutions.count > 1 || attempts >= 2048 { break }
                }
            }
        }
        visit(0, 0, [])
        return solutions.count == 1 && attempts < 2048 ? solutions[0] : []
    }

    private static func isKanji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isIdeographic || $0 == "々" || $0 == "〆" }
    }
    private static func isKana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) || $0 == "ー" || $0.value == 0x3099 || $0.value == 0x309A }
    }
}
