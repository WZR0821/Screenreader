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
    /// `external`: read from a picture or handed over by a shortcut. Nothing is
    /// shown beforehand, and a screenshot mixes the phone's own labels with the
    /// one message the reader wants translated. Only text that is in a single
    /// language throughout counts; a sentence in another language anywhere
    /// means the translation runs as selected.
    enum Origin: Sendable, Equatable { case keyboard, external }

    /// Only the start of a long text is counted; it decides the language just as well.
    private static let limit = 4_000

    static func dominant(_ text: String, origin: Origin,
                         priority: [TargetLanguage] = AppSettings.defaultLanguagePriority) -> TargetLanguage? {
        let reading = read(text, origin: origin, priority: priority)
        if reading.language == .english, isAnotherLatinLanguage(text, letters: reading.latin) { return nil }
        return reading.language
    }

    /// Whether the text is written in `language`. The translation page asks on
    /// every keystroke, so the slower check of Latin text only runs when the
    /// answer depends on it.
    static func isWritten(_ text: String, in language: TargetLanguage, origin: Origin,
                          priority: [TargetLanguage] = AppSettings.defaultLanguagePriority) -> Bool {
        let reading = read(text, origin: origin, priority: priority)
        guard reading.language == language else { return false }
        return language != .english || !isAnotherLatinLanguage(text, letters: reading.latin)
    }

    private static func read(_ text: String, origin: Origin,
                             priority: [TargetLanguage]) -> (language: TargetLanguage?, latin: Int) {
        let strict = origin == .external
        var kana = 0, han = 0, latin = 0, other = 0
        var counts = [Int](repeating: 0, count: Script.count)
        // Latin words in a row with no kanji, kana or line break between them.
        // Four or more are a phrase to translate, not a product name.
        var letters = 0, words = 0, phrase = 0
        func endWord() {
            if letters >= 2 { words += 1; phrase = max(phrase, words) }
            letters = 0
        }
        for scalar in text.unicodeScalars.prefix(limit) {
            let value = scalar.value
            switch value {
            // Kana with their long-vowel and repeat marks, full and half width.
            case 0x3041...0x3096, 0x309D...0x309F, 0x30A1...0x30FA, 0x30FC...0x30FF, 0xFF66...0xFF9F:
                kana += 1; endWord(); words = 0
            // 々 and 〇 are written among kanji in both languages.
            case 0x3005...0x3007, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF:
                han += 1; endWord(); words = 0
                if let script = table[value] { counts[script.rawValue] += 1 }
            case 0x41...0x5A, 0x61...0x7A, 0xFF21...0xFF3A, 0xFF41...0xFF5A: latin += 1; letters += 1
            case 0xC0...0x24F where value != 0xD7 && value != 0xF7: latin += 1; letters += 1
            case 0x0A, 0x0D, 0x2028, 0x2029: endWord(); words = 0
            default:
                endWord()
                if value > 0x7F, scalar.properties.isAlphabetic { other += 1 }
            }
        }
        endWord()
        // A kanji or kana carries about as much as a short word.
        let cjk = (kana + han) * 4
        let total = cjk + latin + other * 2
        // A line of Korean or Russian in a screenshot is a message to translate.
        guard total > 0, cjk + latin > 0,
              strict ? other <= 2 : Double(other * 2) / Double(total) <= 0.3 else { return (nil, latin) }
        let share = Double(cjk) / Double(cjk + latin)
        // Typed Chinese may carry a few English terms ("这个 bug 怎么修"), but
        // "帮我翻译 hello world" asks for the English to be translated.
        if share >= (strict ? 0.9 : 0.7) {
            if strict, phrase >= 4 { return (nil, latin) }
            return (chineseOrJapanese(kana: kana, counts: counts, origin: origin, priority: priority), latin)
        }
        return (share <= (strict ? 0.05 : 0.15) && latin >= 2 ? .english : nil, latin)
    }

    private static func chineseOrJapanese(kana: Int, counts: [Int], origin: Origin,
                                          priority: [TargetLanguage]) -> TargetLanguage? {
        func count(_ script: Script) -> Int { counts[script.rawValue] }
        let japanese = kana + 2 * count(.japaneseOnly)
        let chinese = 2 * (count(.chineseSimplified) + count(.chineseTraditional) + count(.chineseCommon))
        let simplified = count(.chineseSimplified) + count(.sharedSimplified)
        let traditional = count(.chineseTraditional) + count(.sharedTraditional)
        if japanese == 0, chinese == 0 {
            // Every character is one both languages use. Forms that simplified
            // Chinese does not have (東, 語) rule it out; together with forms
            // traditional Chinese does not have (国, 学) only Japanese is left.
            if traditional > 0 { return simplified > 0 ? .japanese : nil }
            guard origin == .keyboard else { return nil }
            return priority.first { $0 == .simplifiedChinese || $0 == .japanese }
        }
        let strict = origin == .external
        // Both languages in one text: leave the choice to the user.
        guard min(japanese, chinese) * (strict ? 10 : 2) < max(japanese, chinese) else { return nil }
        if japanese > chinese {
            // Simplified forms are never Japanese: someone else's message.
            return strict && count(.chineseSimplified) > 1 ? nil : .japanese
        }
        // One の is decoration. More kana is a Japanese line in a Chinese screen.
        if strict, kana > 1 { return nil }
        // Traditional Chinese is not the 中文 this app translates into.
        return traditional > simplified ? nil : .simplifiedChinese
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
