import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Works out which of the three supported languages a text is written in, so
/// that text already in the target language can be sent somewhere useful.
///
/// The answer changes what the user asked for, so it has to be right or absent:
/// anything mixed, short on evidence or outside the three languages gives nil,
/// and the translation then runs exactly as selected.
enum LanguageGuess {
    /// Where the text came from.
    ///
    /// `keyboard`: typed or pasted into the box. The page shows where it will
    /// go before anything is sent, and kanji both languages share follow the
    /// priority order.
    ///
    /// `external`: read from a picture or handed over by a shortcut, with
    /// nothing shown beforehand. A screenshot mixes what the reader wants with
    /// the phone's own labels, people's names and links, so links and @handles
    /// are left out, and short lines (已读, 翻译帖子, a name) only count when
    /// there is nothing longer. The language most of the rest is in decides,
    /// except the reader's own language, the first in the priority: leaving
    /// it would keep a message in the next language untranslated, so it only
    /// counts when every line is in it.
    enum Origin: Sendable, Equatable { case keyboard, external }

    /// Only the start of a long text is counted; it decides the language just as well.
    private static let limit = 4_000
    /// A line that weighs no more than four kanji or sixteen letters is a
    /// label, a name or a time rather than what the screen is about.
    private static let shortLine = 16

    static func dominant(_ text: String, origin: Origin,
                         priority: [TargetLanguage] = AppSettings.defaultLanguagePriority) -> TargetLanguage? {
        let reading = read(text, origin: origin, priority: priority)
        if reading.language == .english, isAnotherLatinLanguage(reading.text, letters: reading.latin) { return nil }
        return reading.language
    }

    /// Whether the text is written in `language`. The translation page asks on
    /// every keystroke, so the slower check of Latin text only runs when the
    /// answer depends on it.
    static func isWritten(_ text: String, in language: TargetLanguage, origin: Origin,
                          priority: [TargetLanguage] = AppSettings.defaultLanguagePriority) -> Bool {
        let reading = read(text, origin: origin, priority: priority)
        guard reading.language == language else { return false }
        return language != .english || !isAnotherLatinLanguage(reading.text, letters: reading.latin)
    }

    /// The language, the Latin letters it was decided on, and the text it was read from.
    private static func read(_ text: String, origin: Origin,
                             priority: [TargetLanguage]) -> (language: TargetLanguage?, latin: Int, text: String) {
        let order = AppSettings.normalizedPriority(priority)
        guard origin == .external else {
            let all = Tally.lines(of: text).all
            let shared = order.first { $0 == .simplifiedChinese || $0 == .japanese }
            return (language(of: all, strict: false, sharedKanji: shared), all.latin, text)
        }
        let clean = withoutAddresses(text)
        let lines = Tally.lines(of: clean)
        let main = lines.long.weight > 0 ? lines.long : lines.all
        guard let found = language(of: main, strict: false, sharedKanji: nil),
              found != order.first || language(of: lines.all, strict: true, sharedKanji: nil) == found
        else { return (nil, main.latin, clean) }
        return (found, main.latin, clean)
    }

    /// The language of what was counted, or nil. `strict` asks for all of it
    /// to be in that one language.
    private static func language(of tally: Tally, strict: Bool, sharedKanji: TargetLanguage?) -> TargetLanguage? {
        let total = tally.weight
        // A line of Korean or Russian in a screenshot is a message to translate.
        guard total > 0, tally.cjk + tally.latin > 0,
              strict ? tally.other <= 2 : Double(tally.other * 2) / Double(total) <= 0.3 else { return nil }
        let share = Double(tally.cjk) / Double(tally.cjk + tally.latin)
        // Typed Chinese may carry a few English terms ("这个 bug 怎么修"), but
        // "帮我翻译 hello world" asks for the English to be translated.
        if share >= (strict ? 0.9 : 0.7) {
            if strict, tally.phrase >= 4 { return nil }
            return chineseOrJapanese(tally, strict: strict, sharedKanji: sharedKanji)
        }
        return share <= (strict ? 0.05 : 0.15) && tally.latin >= 2 ? .english : nil
    }

    private static func chineseOrJapanese(_ tally: Tally, strict: Bool, sharedKanji: TargetLanguage?) -> TargetLanguage? {
        func count(_ script: Script) -> Int { tally.counts[script.rawValue] }
        let japanese = tally.kana + 2 * count(.japaneseOnly)
        let chinese = 2 * (count(.chineseSimplified) + count(.chineseTraditional) + count(.chineseCommon))
        let simplified = count(.chineseSimplified) + count(.sharedSimplified)
        let traditional = count(.chineseTraditional) + count(.sharedTraditional)
        if japanese == 0, chinese == 0 {
            // Every character is one both languages use. Forms that simplified
            // Chinese does not have (東, 語) rule it out; together with forms
            // traditional Chinese does not have (国, 学) only Japanese is left.
            if traditional > 0 { return simplified > 0 ? .japanese : nil }
            return sharedKanji
        }
        // Both languages in one text: leave the choice to the user.
        guard min(japanese, chinese) * (strict ? 10 : 2) < max(japanese, chinese) else { return nil }
        if japanese > chinese {
            // Simplified forms are never Japanese: someone else's message.
            return strict && count(.chineseSimplified) > 1 ? nil : .japanese
        }
        // One の is decoration. More kana is a Japanese line in a Chinese screen.
        if strict, tally.kana > 1 { return nil }
        // Traditional Chinese is not the 中文 this app translates into.
        return traditional > simplified ? nil : .simplifiedChinese
    }

    /// What a stretch of text holds.
    private struct Tally {
        var kana = 0, han = 0, latin = 0, other = 0
        var counts = [Int](repeating: 0, count: Script.count)
        /// The most Latin words in a row with no kanji, kana or line break
        /// between them. Four or more are a phrase to translate, not a product name.
        var phrase = 0
        /// A kanji or kana carries about as much as a short word.
        var cjk: Int { (kana + han) * 4 }
        var weight: Int { cjk + latin + other * 2 }

        mutating func add(_ line: Tally) {
            kana += line.kana; han += line.han; latin += line.latin; other += line.other
            phrase = max(phrase, line.phrase)
            for index in counts.indices { counts[index] += line.counts[index] }
        }

        /// Counts the start of `text`: all of it, and only the lines longer than `shortLine`.
        static func lines(of text: String) -> (all: Tally, long: Tally) {
            var all = Tally(), long = Tally(), line = Tally()
            var letters = 0, words = 0
            func endWord() {
                if letters >= 2 { words += 1; line.phrase = max(line.phrase, words) }
                letters = 0
            }
            func endLine() {
                endWord(); words = 0
                all.add(line)
                if line.weight > LanguageGuess.shortLine { long.add(line) }
                line = Tally()
            }
            for scalar in text.unicodeScalars.prefix(LanguageGuess.limit) {
                let value = scalar.value
                switch value {
                // Kana with their long-vowel and repeat marks, full and half width.
                case 0x3041...0x3096, 0x309D...0x309F, 0x30A1...0x30FA, 0x30FC...0x30FF, 0xFF66...0xFF9F:
                    line.kana += 1; endWord(); words = 0
                // 々 and 〇 are written among kanji in both languages.
                case 0x3005...0x3007, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF:
                    line.han += 1; endWord(); words = 0
                    if let script = LanguageGuess.table[value] { line.counts[script.rawValue] += 1 }
                case 0x41...0x5A, 0x61...0x7A, 0xFF21...0xFF3A, 0xFF41...0xFF5A: line.latin += 1; letters += 1
                case 0xC0...0x24F where value != 0xD7 && value != 0xF7: line.latin += 1; letters += 1
                case 0x0A, 0x0D, 0x2028, 0x2029: endLine()
                default:
                    endWord()
                    if value > 0x7F, scalar.properties.isAlphabetic { line.other += 1 }
                }
            }
            endLine()
            return (all, long)
        }
    }

    /// Links, e-mail addresses, @handles and Latin #tags say nothing about the
    /// language around them, and a domain or a handle reads like English.
    private static let addresses: NSRegularExpression? = {
        let url = "[A-Za-z0-9\\-._~:/?#\\[\\]@!$&'()*+,;=%]"
        let domains = "com|net|org|jp|cn|io|co|me|info|edu|gov|ac|tv|app|dev|ly|gl|be|uk|tw|hk|kr|ai|us|de|fr|asia|xyz|site|top|news"
        let pattern = [
            "(?:https?://|www\\.)\(url)+",
            "(?<![A-Za-z0-9._%+\\-])[A-Za-z0-9._%+\\-]++@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}",
            "(?<![A-Za-z0-9.\\-@])(?:[A-Za-z0-9\\-]+\\.)+(?:\(domains))(?![A-Za-z0-9\\-])(?:/\(url)*)?",
            "[@＠][A-Za-z0-9_]{2,}",
            "[#＃][A-Za-z0-9_]+",
        ].joined(separator: "|")
        return try? NSRegularExpression(pattern: pattern)
    }()

    private static func withoutAddresses(_ text: String) -> String {
        let start = String(text.unicodeScalars.prefix(limit))
        guard let addresses else { return start }
        return addresses.stringByReplacingMatches(in: start, range: NSRange(start.startIndex..., in: start), withTemplate: " ")
    }

    /// French, Spanish or German also use Latin letters. Treating them as
    /// English would stop a wanted translation into English.
    private static func isAnotherLatinLanguage(_ text: String, letters: Int) -> Bool {
        #if canImport(NaturalLanguage)
        guard letters >= 20 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(600)))
        guard let best = recognizer.languageHypotheses(withMaximum: 1).first else { return false }
        return best.key != .english && best.value >= 0.8
        #else
        return false
        #endif
    }

    private enum Script: Int, CaseIterable {
        case chineseSimplified, chineseTraditional, chineseCommon, sharedSimplified, sharedTraditional, japaneseOnly
        static let count = allCases.count
        var characters: String {
            switch self {
            case .chineseSimplified: return LanguageScriptTables.chineseSimplified
            case .chineseTraditional: return LanguageScriptTables.chineseTraditional
            case .chineseCommon: return LanguageScriptTables.chineseCommon
            case .sharedSimplified: return LanguageScriptTables.sharedSimplified
            case .sharedTraditional: return LanguageScriptTables.sharedTraditional
            case .japaneseOnly: return LanguageScriptTables.japaneseOnly
            }
        }
    }

    private static let table: [UInt32: Script] = {
        var table: [UInt32: Script] = [:]
        for script in Script.allCases {
            for scalar in script.characters.unicodeScalars { table[scalar.value] = script }
        }
        return table
    }()
}

/// The settings a translation actually runs with, and why they differ from
/// the ones selected.
struct TargetResolution: Equatable {
    var settings: AppSettings
    /// The target the user selected.
    var requested: TargetLanguage
    var switched: Bool { settings.target != requested }
    /// Shown with the result, so a changed target is never a surprise.
    var note: String? {
        switched ? "原文是\(requested.title)，已按语言优先级改译为\(settings.target.title)。" : nil
    }
}

extension AppSettings {
    static let defaultLanguagePriority: [TargetLanguage] = [.simplifiedChinese, .japanese, .english]

    /// Every language exactly once, keeping the saved order.
    static func normalizedPriority(_ saved: [TargetLanguage]) -> [TargetLanguage] {
        var order: [TargetLanguage] = []
        for language in saved + defaultLanguagePriority where !order.contains(language) { order.append(language) }
        return order
    }

    /// What text already in `language` is translated into instead.
    func fallbackTarget(for language: TargetLanguage) -> TargetLanguage {
        Self.normalizedPriority(languagePriority).first { $0 != language } ?? language
    }

    /// With 自动识别, text that is already in the target language goes to the
    /// first other language in the priority order. An explicit source language
    /// is a decision and is never overridden.
    func resolvingTarget(for text: String, origin: LanguageGuess.Origin) -> TargetResolution {
        var resolution = TargetResolution(settings: self, requested: target)
        guard smartTarget, source == .automatic,
              LanguageGuess.isWritten(text, in: target, origin: origin, priority: languagePriority) else { return resolution }
        resolution.settings.source = SourceLanguage(target: target)
        resolution.settings.target = fallbackTarget(for: target)
        return resolution
    }
}
