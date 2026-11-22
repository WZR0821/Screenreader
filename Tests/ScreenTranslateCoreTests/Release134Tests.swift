import XCTest
#if canImport(ScreenTranslateCore)
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

/// 1.3.4: 语言优先级. With 自动识别, text that is already in the target
/// language goes to the first other language in a user-ordered list.
final class Release134Tests: XCTestCase {
    private func guess(_ text: String, _ origin: LanguageGuess.Origin = .keyboard,
                       priority: [TargetLanguage] = AppSettings.defaultLanguagePriority) -> TargetLanguage? {
        LanguageGuess.dominant(text, origin: origin, priority: priority)
    }

    // MARK: Which language a text is in

    func testSimplifiedChineseIsRecognisedFromTypingAndFromScreenshots() {
        for text in ["你好", "谢谢", "今天天气不错，我们去公园吧。", "我想去图书馆借两本书", "这个东西多少钱？",
                     "为什么会这样", "它是一只猫", "我很好", "帮我看看这个 bug 怎么修",
                     "国务院发布新规定\n自 2027 年 1 月 1 日起施行"] {
            XCTAssertEqual(guess(text, .keyboard), .simplifiedChinese, text)
            XCTAssertEqual(guess(text, .external), .simplifiedChinese, text)
        }
        // Typed Chinese may carry English terms.
        for text in ["我昨天在京东买了一台 iPhone 16 Pro Max，感觉还不错", "这个 API 的 response 是什么格式"] {
            XCTAssertEqual(guess(text, .keyboard), .simplifiedChinese, text)
        }
        // A Chinese request about English text asks for that text in Chinese.
        for text in ["帮我翻译 hello world", "请翻译：Good morning", "这句话是什么意思 What does this mean"] {
            XCTAssertNil(guess(text, .keyboard), text)
            XCTAssertNil(guess(text, .external), text)
        }
    }

    func testAScreenshotCountsOnlyWhenItIsInOneLanguageThroughout() {
        // Chinese is first in the default priority, so a Chinese screen
        // still has to be Chinese throughout. A settings screen, with a product name.
        let settings = "设置\n无线局域网\n蓝牙\n蜂窝网络\n个人热点\n通知\n声音与触感\n专注模式\n屏幕使用时间\nApp Store\n通用"
        XCTAssertEqual(guess(settings, .external), .simplifiedChinese)
        // The Shortcuts editor the action button test takes a screenshot of.
        XCTAssertEqual(guess("读屏全文\n完成\n截屏\n翻译 截屏 全文\n在“快速查看”中显示\n翻译截图全文\n搜索操作", .external), .simplifiedChinese)

        // A Chinese chat with one Japanese message: that message is why the
        // screenshot was taken, however much Chinese surrounds it.
        let chat = "微信\n王老师\n昨天 下午 3:20\n明天的会议改到几点了？\n我这边下午都有空，你们定好时间告诉我一声就行。\n"
            + "田中さんからの返信です\n明日の会議は午後三時からです。よろしくお願いします。\n好的，谢谢！那我们明天见。\n按住 说话"
        XCTAssertNil(guess(chat, .external))
        let long = String(repeating: "这是一段很长的中文聊天记录，我们说了很多话。\n", count: 40)
        XCTAssertEqual(guess(long, .external), .simplifiedChinese)
        XCTAssertNil(guess(long + "ありがとう", .external), "One short Japanese line is enough")
        XCTAssertEqual(guess(long + "ありがとう", .keyboard), .simplifiedChinese, "Typed text shows its target before it is sent")
        XCTAssertEqual(guess(long + "优の良品", .external), .simplifiedChinese, "A single の is decoration")

        // A Chinese page quoting an English sentence, and a word list.
        let quote = String(repeating: "这是一段很长的中文说明，介绍下面这句话的背景。\n", count: 6)
        XCTAssertNil(guess(quote + "Please keep this ticket until you leave.", .external))
        XCTAssertEqual(guess(quote + "Please keep this ticket until you leave.", .keyboard), .simplifiedChinese)
        XCTAssertEqual(guess(quote + "iPhone 16 Pro Max", .external), .simplifiedChinese, "A product name is not a phrase")
        XCTAssertNil(guess("apple 苹果\nbanana 香蕉\norange 橙子\ngrape 葡萄", .external))
        XCTAssertNil(guess("我昨天在京东买了一台 iPhone 16 Pro Max，感觉还不错", .external))

        // Japanese screens. Since 1.4.0 only the reader's own language, first
        // in the priority, needs the whole screen; for any other the language
        // most of it is in decides (Release140ScreenTests).
        let japanese = String(repeating: "本日は定休日です。またのご来店をお待ちしております。\n", count: 8)
        XCTAssertEqual(guess(japanese, .external), .japanese)
        XCTAssertEqual(guess(japanese + "这个东西多少钱？我们明天再说吧。", .external), .japanese)
        XCTAssertEqual(guess("iPhoneのバッテリーを交換する", .external), .japanese)
        XCTAssertEqual(guess(japanese + "Please keep this ticket until you leave.", .external), .japanese)

        // English with a word or two of anything else.
        let english = String(repeating: "Please keep this ticket until you leave the station. ", count: 4)
        XCTAssertEqual(guess(english, .external), .english)
        XCTAssertNil(guess(english + "谢谢惠顾，欢迎再次光临", .external))
        XCTAssertNil(guess(String(repeating: "这是一段很长的中文说明。", count: 20) + "안녕하세요 반갑습니다 감사합니다", .external))
    }

    func testJapaneseIsRecognisedFromKanaAndFromJapaneseOnlyKanji() {
        for text in ["ありがとう", "コーヒー", "ラーメン", "時々そうなる", "今日は天気がいいですね。", "東京駅で電車に乗る", "営業中", "駅前広場",
                     "首相、訪米へ 日米首脳会談で関税協議", "ﾊﾝｶｸｶﾅ",
                     "本日は定休日です。またのご来店をお待ちしております。"] {
            XCTAssertEqual(guess(text, .keyboard), .japanese, text)
            XCTAssertEqual(guess(text, .external), .japanese, text)
        }
        XCTAssertEqual(guess("iPhoneのバッテリーを交換する", .keyboard), .japanese)
    }

    func testEnglishIsRecognisedAndOtherLatinLanguagesAreNot() {
        for text in ["Hello", "OK", "Good morning.", "Please translate this short paragraph.",
                     "The quick brown fox jumps over the lazy dog.", "Total: $12.50 (tax included)"] {
            XCTAssertEqual(guess(text), .english, text)
            XCTAssertEqual(guess(text, .external), .english, text)
        }
        // Treating these as English would stop a wanted translation into English.
        for text in ["Bonjour, je voudrais réserver une table pour deux personnes ce soir, s'il vous plaît.",
                     "Guten Morgen, ich möchte bitte ein Zimmer für zwei Nächte reservieren.",
                     "Buenos días, ¿dónde está la estación de tren más cercana, por favor?"] {
            XCTAssertNil(guess(text), text)
        }
    }

    func testKanjiBothLanguagesShareFollowThePriorityOnlyWhenTyped() {
        // Every character here is written the same way in Chinese and Japanese.
        for text in ["我是学生", "定休日", "中国人民", "山田", "学生"] {
            XCTAssertEqual(guess(text, .keyboard), .simplifiedChinese, text)
            XCTAssertEqual(guess(text, .keyboard, priority: [.japanese, .simplifiedChinese, .english]), .japanese, text)
            XCTAssertEqual(guess(text, .keyboard, priority: [.english, .japanese, .simplifiedChinese]), .japanese, text)
            // From a screenshot or a shortcut there is no telling: leave it alone.
            XCTAssertNil(guess(text, .external), text)
        }
    }

    func testFormsSimplifiedChineseDoesNotHaveAreNeverCalledChinese() {
        // 東, 語 and 車 are traditional forms: Japanese or traditional Chinese.
        for text in ["東京都", "日本語", "電車"] {
            XCTAssertNil(guess(text, .keyboard), text)
            XCTAssertNil(guess(text, .external), text)
        }
        // With forms traditional Chinese does not have either (国, 学), only Japanese is left.
        for text in ["国語学習", "東京大学", "会議室"] {
            XCTAssertEqual(guess(text, .keyboard), .japanese, text)
            XCTAssertEqual(guess(text, .external), .japanese, text)
        }
    }

    func testTraditionalChineseIsNotTheSimplifiedTarget() {
        for text in ["這個東西多少錢？", "我們今天去圖書館借書", "請問洗手間在哪裡", "謝謝你的幫忙"] {
            XCTAssertNil(guess(text, .keyboard), text)
            XCTAssertNil(guess(text, .external), text)
        }
    }

    func testMixedOrUnsupportedTextGivesNoAnswer() {
        for text in ["", "   \n", "12345 !!! 😀", "What does 你好 mean?", "How do you say 谢谢 in Japanese?",
                     "优の良品", "这个东西多少钱？これはいくらですか。", "안녕하세요, 반갑습니다", "Привет, как дела?",
                     "مرحبا بالعالم", "你好 안녕하세요 반갑습니다"] {
            XCTAssertNil(guess(text, .keyboard), text)
            XCTAssertNil(guess(text, .external), text)
        }
    }

    func testLongTextIsDecidedByItsStart() {
        let chinese = String(repeating: "这是一段很长的中文内容。", count: 600)
        XCTAssertEqual(guess(chinese + String(repeating: "これは日本語です。", count: 2_000)), .simplifiedChinese)
        let started = Date()
        for _ in 0..<50 { _ = guess(chinese) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "The translation page asks on every keystroke")
    }

    func testCharacterTablesDoNotOverlapAndHoldTheExpectedForms() {
        let tables: [(String, String)] = [
            (LanguageScriptTables.chineseSimplified, "这们说对发"), (LanguageScriptTables.chineseTraditional, "們說對發嗎"),
            (LanguageScriptTables.chineseCommon, "你很它哪怎"), (LanguageScriptTables.sharedSimplified, "国学会点来"),
            (LanguageScriptTables.sharedTraditional, "東語時間車"), (LanguageScriptTables.japaneseOnly, "駅円図楽気")]
        var seen = Set<Character>()
        for (table, samples) in tables {
            let characters = Set(table)
            XCTAssertEqual(characters.count, table.count, "No character twice")
            XCTAssertTrue(seen.isDisjoint(with: characters))
            seen.formUnion(characters)
            XCTAssertTrue(characters.isSuperset(of: samples), samples)
            XCTAssertFalse(table.contains { $0.isWhitespace || $0 == "\\" }, "Line continuations must not leak in")
        }
        // Characters every one of the three languages writes the same way say nothing.
        XCTAssertTrue(seen.isDisjoint(with: "人大中日本山水火木金土一二三"))
    }

    // MARK: Where the translation goes

    func testChineseTypedWithChineseTargetGoesToTheNextLanguage() {
        let settings = AppSettings()
        XCTAssertEqual(settings.source, .automatic); XCTAssertEqual(settings.target, .simplifiedChinese)
        XCTAssertTrue(settings.smartTarget)
        XCTAssertEqual(settings.languagePriority, [.simplifiedChinese, .japanese, .english])
        let resolved = settings.resolvingTarget(for: "你好，今天过得怎么样？", origin: .keyboard)
        XCTAssertTrue(resolved.switched)
        XCTAssertEqual(resolved.requested, .simplifiedChinese)
        XCTAssertEqual(resolved.settings.target, .japanese)
        XCTAssertEqual(resolved.settings.source, .chinese, "The request names the source instead of detecting it again")
        XCTAssertEqual(resolved.note, "原文是中文，已按语言优先级改译为日语。")
        var expected = settings; expected.source = .chinese; expected.target = .japanese
        XCTAssertEqual(resolved.settings, expected, "Nothing else changes")
    }

    func testOtherLanguagesKeepTheSelectedTarget() {
        let settings = AppSettings()
        for text in ["Hello", "今日は天気がいいですね。", "東京都", "這個東西多少錢？", "What does 你好 mean?", ""] {
            let resolved = settings.resolvingTarget(for: text, origin: .keyboard)
            XCTAssertFalse(resolved.switched, text); XCTAssertNil(resolved.note)
            XCTAssertEqual(resolved.settings, settings, text)
        }
        // Kanji-only text from a screenshot may be Japanese: it stays as selected.
        XCTAssertFalse(settings.resolvingTarget(for: "定休日", origin: .external).switched)
        XCTAssertTrue(settings.resolvingTarget(for: "定休日", origin: .keyboard).switched)
    }

    func testEveryTargetFallsBackToTheFirstOtherLanguage() {
        var settings = AppSettings()
        settings.target = .japanese
        var resolved = settings.resolvingTarget(for: "今日は天気がいいですね。", origin: .keyboard)
        XCTAssertEqual(resolved.settings.target, .simplifiedChinese); XCTAssertEqual(resolved.settings.source, .japanese)
        XCTAssertEqual(resolved.note, "原文是日语，已按语言优先级改译为中文。")
        XCTAssertFalse(settings.resolvingTarget(for: "你好，今天过得怎么样？", origin: .keyboard).switched)
        settings.target = .english
        resolved = settings.resolvingTarget(for: "Good morning.", origin: .external)
        XCTAssertEqual(resolved.settings.target, .simplifiedChinese); XCTAssertEqual(resolved.settings.source, .english)
        XCTAssertFalse(settings.resolvingTarget(for: "Bonjour, je voudrais réserver une table pour deux personnes ce soir.",
                                                origin: .keyboard).switched)

        settings.languagePriority = [.english, .japanese, .simplifiedChinese]
        settings.target = .simplifiedChinese
        XCTAssertEqual(settings.resolvingTarget(for: "这个东西多少钱？", origin: .keyboard).settings.target, .english)
        settings.target = .english
        XCTAssertEqual(settings.resolvingTarget(for: "Good morning.", origin: .keyboard).settings.target, .japanese)
        for language in TargetLanguage.allCases {
            XCTAssertNotEqual(settings.fallbackTarget(for: language), language)
        }
    }

    func testExplicitSourceOrSwitchedOffNeverChangesTheTarget() {
        var settings = AppSettings()
        settings.source = .chinese
        XCTAssertFalse(settings.resolvingTarget(for: "这个东西多少钱？", origin: .keyboard).switched,
                       "A selected source language is a decision")
        settings.source = .automatic; settings.smartTarget = false
        let resolved = settings.resolvingTarget(for: "这个东西多少钱？", origin: .keyboard)
        XCTAssertFalse(resolved.switched); XCTAssertEqual(resolved.settings, settings)
    }

    func testResolvedSettingsDriveThePromptAndTheCacheKey() throws {
        let settings = AppSettings()
        let resolved = settings.resolvingTarget(for: "这个东西多少钱？", origin: .keyboard).settings
        let prompt = try TextPreparation.instructions(settings: resolved)
        XCTAssertTrue(prompt.contains("Translate every part into Japanese."), prompt)
        XCTAssertTrue(prompt.contains("The source language is \(SourceLanguage.chinese.promptName)"), prompt)
        XCTAssertTrue(try TextPreparation.instructions(settings: settings).contains("Translate every part into Simplified Chinese."))
        let selectedKey = try TranslationCache.key(text: "这个东西多少钱？", settings: settings, apiKey: "k",
                                                   readingBlocks: nil, fromImageText: false)
        let resolvedKey = try TranslationCache.key(text: "这个东西多少钱？", settings: resolved, apiKey: "k",
                                                   readingBlocks: nil, fromImageText: false)
        XCTAssertNotEqual(selectedKey, resolvedKey, "A Chinese reply cached earlier must not come back as the Japanese one")
        // The prompts themselves did not change, so translations cached by 1.3.3 stay valid.
        XCTAssertEqual(TranslationPrompts.revision, "2026-11-screenreader-1.3.3-b31")
    }

    // MARK: Saved settings and records

    func testPrioritySurvivesSavingAndOldSettingsGetTheDefault() throws {
        var settings = AppSettings()
        settings.languagePriority = [.english, .simplifiedChinese, .japanese]; settings.smartTarget = false
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.languagePriority, [.english, .simplifiedChinese, .japanese])
        XCTAssertFalse(restored.smartTarget); XCTAssertEqual(restored, settings)

        // Settings saved by 1.3.3 have neither key.
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as! [String: Any]
        object.removeValue(forKey: "languagePriority"); object.removeValue(forKey: "smartTarget")
        let old = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.languagePriority, AppSettings.defaultLanguagePriority); XCTAssertTrue(old.smartTarget)

        // A damaged or future list keeps what it can and never loses a language.
        object["languagePriority"] = ["日本語", "Klingon", "日本語"]
        let damaged = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(damaged.languagePriority, [.japanese, .simplifiedChinese, .english])
        XCTAssertEqual(AppSettings.normalizedPriority([]), AppSettings.defaultLanguagePriority)
        XCTAssertEqual(AppSettings.normalizedPriority([.english]), [.english, .simplifiedChinese, .japanese])
    }

    func testOldRecordsOpenWithoutATargetNote() throws {
        var result = TranslationResult(original: "你好", translated: "こんにちは", sourceLanguages: "中文", target: "日语",
                                       engine: "fixture", elapsed: 1, warning: nil)
        XCTAssertNil(result.targetNote)
        result.targetNote = "原文是中文，已按语言优先级改译为日语。"
        let restored = try JSONDecoder().decode(TranslationResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(restored, result)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
        object.removeValue(forKey: "targetNote")
        let old = try JSONDecoder().decode(TranslationResult.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.targetNote); XCTAssertEqual(old.translated, "こんにちは")
        // A block of that record is translated again in the record's language.
        let review = try TranslationReview.settings(for: restored, using: AppSettings())
        XCTAssertEqual(review.target, .japanese); XCTAssertEqual(review.source, .chinese)
    }
}
