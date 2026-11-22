import XCTest
#if canImport(ScreenTranslateCore)
@testable import ScreenTranslateCore
#else
@testable import ScreenTranslate
#endif

/// 1.4.0 (33): 语言优先级 for the action button, screenshots and 识图. A
/// screen holds the phone's own labels, names and links as well as what the
/// reader wants; the language most of the content is in decides, and only the
/// reader's own language, first in the priority, still needs the whole screen.
/// (Not the 1.4.0 test package of build 28, whose tests are in Release140Tests.)
final class Release140ScreenTests: XCTestCase {
    // What the app's OCRService reads from Tests/Fixtures/screen-priority-v1
    // on a Mac. The simulator reads a few characters differently; the
    // integration tests use the pictures themselves.
    /// ja-timeline-zh-ui.png
    static let japaneseTimeline = """
        为你推荐

        さくら日和 @sakura_biyori・3小町今日は久しぶりに鎌倉まで足を延ばしました。紅葉はまだ少し早かったけど、海沿いの道を歩くだけで気分がすっきりします。＃鎌倉＃週末散歩

        12

        48

        1,203

        3.1万

        東京グルメ速報 @tokyo_gourmet・5小肘【新店情報】渋谷駅から徒歩3分の場所に、行列のできるラーメン店が2号店をオープン。平日は11時から23時まで営業、土日は売り切れ次第終了とのことです。詳しくはこちらexample.jp/ramen/2nd

        35

        210

        3,482

        12万

        Kenji Tanaka @kenji_dev • 8/MJ iPhoneのショートカットでスクリーンショットを翻訳できるのが便利すぎる。Apple Intelligenceが日本語にもっと対応したら、さらに使いやすくなりそう。

        翻洋帖子

        4

        17

        256

        9,870

        ゆうき ＠yuki0412・11小日明日の試験、緊張して眠れない。とりあえず早めに寝ます。おやすみなさい。

        2

        5

        88

        1,540
        """

    /// ja-chat-zh-ui.png
    static let japaneseChat = """
        山田 由美

        昨天下午3:20

        お疲れさまです！明日の打ち合わせ、10時からで大丈夫ですか？

        はい、大丈夫です。資料は今夜中に送りますね。

        ありがとうございます。会議室は3階の第2会議室を予約しました。

        了解です！

        已读

        下午 6:02

        あと、駅前のカフェで少し早めに集まりませんか？

        按住 说话
        """

    /// ja-chat-sparse-zh-ui.png
    static let japaneseShortChat = """
        佐藤健

        今天上午9:12

        明日よろしくね！

        了解です！

        已读

        按住 说话
        """

    /// zh-chat-with-ja.png
    static let chineseChatWithJapanese = """
        研究会交流群（12）

        下午 2:41

        王老师

        明天的读书会改到下午三点，地点还是图书馆二楼。

        收到，我会提前把报告发到群里。

        田中

        すみません、明日は授業があるので、少し遅れて参加します。資料は先に読んでおきます。

        王老师

        没问题，大家到齐以后再开始讨论。

        好的，谢谢老师！

        按住 说话

        〇〇
        """

    /// zh-article.png
    static let chineseArticle = """
        X

        冬季出行提示：这几条建议请收好

        城市生活指南11月22日 08:30

        进入十一月下旬，各地气温明显下降，早晚温差较大。出门前请关注天气预报，适当增添衣物，特别是老人和孩子要注意保暖。

        乘坐地铁和公交时，请提前查询首末班车时间。部分线路在节假日会调整运营安排，建议使用官方应用查看实时信息。如遇雨雪天气，道路湿滑，驾车时请减速慢行，与前车保持足够的安全距离。

        阅读原文 city.example.cn/winter
        """

    /// en-timeline-zh-ui.png
    static let englishTimeline = """
        为你推荐

        Nora Hughes @norahughes・2小町

        Finally finished the long trail along the coast this weekend. My legs hate me, but the view from the last hill was worth every step.

        翻译帖子

        9

        31

        402

        2.4万

        Transit Weekly @transitweekly • 4/MJ The night bus pilot is being extended until March. Riders can check the new timetable on the city website before planning late trips.翻洋呫子

        9

        31

        402

        2.4万

        Sam Ortiz @samortiz_dev • 7/MJ Small reminder that a good error message is part of the feature, not an afterthought. Tell people what happened and what to do next.

        9

        31

        402

        2.45
        """

    private func resolve(_ text: String, selected: TargetLanguage,
                         priority: [TargetLanguage] = AppSettings.defaultLanguagePriority) -> TargetResolution {
        var settings = AppSettings(); settings.target = selected; settings.languagePriority = priority
        return settings.resolvingTarget(for: text, origin: .external)
    }

    private func guess(_ text: String, _ origin: LanguageGuess.Origin = .external,
                       priority: [TargetLanguage] = AppSettings.defaultLanguagePriority) -> TargetLanguage? {
        LanguageGuess.dominant(text, origin: origin, priority: priority)
    }

    func testJapaneseScreensWithChineseLabelsGoToChinese() {
        for (name, text) in [("timeline", Self.japaneseTimeline), ("chat", Self.japaneseChat), ("short chat", Self.japaneseShortChat)] {
            let resolution = resolve(text, selected: .japanese)
            XCTAssertEqual(resolution.settings.target, .simplifiedChinese, name)
            XCTAssertEqual(resolution.settings.source, .japanese, name)
            XCTAssertEqual(resolution.note, "原文是日语，已按语言优先级改译为中文。", name)
            // Japanese into Chinese or English needs no change.
            XCTAssertFalse(resolve(text, selected: .simplifiedChinese).switched, name)
            XCTAssertFalse(resolve(text, selected: .english).switched, name)
        }
    }

    func testAnEnglishTimelineWithChineseLabelsGoesToChinese() {
        let resolution = resolve(Self.englishTimeline, selected: .english)
        XCTAssertEqual(resolution.settings.target, .simplifiedChinese)
        XCTAssertEqual(resolution.note, "原文是英语，已按语言优先级改译为中文。")
        XCTAssertFalse(resolve(Self.englishTimeline, selected: .japanese).switched)
    }

    func testAChineseScreenStillNeedsEveryLineInChinese() {
        // The link under the article no longer reads as an English phrase.
        let article = resolve(Self.chineseArticle, selected: .simplifiedChinese)
        XCTAssertEqual(article.settings.target, .japanese)
        XCTAssertEqual(article.note, "原文是中文，已按语言优先级改译为日语。")
        // One Japanese message in a Chinese group chat is why the screenshot
        // was taken. Japanese would leave it untranslated.
        XCTAssertFalse(resolve(Self.chineseChatWithJapanese, selected: .simplifiedChinese).switched)
        XCTAssertFalse(resolve(Self.chineseChatWithJapanese, selected: .japanese).switched, "Most of it is Chinese, not Japanese")
    }

    func testTheReadersOwnLanguageIsTheStrictOne() {
        let japanese = String(repeating: "本日は定休日です。またのご来店をお待ちしております。\n", count: 8)
        let chinese = String(repeating: "这是一段很长的中文聊天记录，我们说了很多话。\n", count: 40)
        let japaneseFirst: [TargetLanguage] = [.japanese, .simplifiedChinese, .english]
        // Chinese first: a Chinese line on a Japanese screen is the reader's
        // own, but a Japanese line on a Chinese screen is a message.
        XCTAssertEqual(guess(japanese + "这个东西多少钱？我们明天再说吧。"), .japanese)
        XCTAssertNil(guess(chinese + "ありがとう"))
        // Japanese first: the other way round.
        XCTAssertNil(guess(japanese + "这个东西多少钱？我们明天再说吧。", priority: japaneseFirst))
        XCTAssertEqual(guess(chinese + "ありがとう", priority: japaneseFirst), .simplifiedChinese)
        XCTAssertEqual(guess(japanese, priority: japaneseFirst), .japanese)
        XCTAssertFalse(resolve(Self.japaneseChat + "\n这个东西多少钱？我们明天再说吧。", selected: .japanese,
                               priority: japaneseFirst).switched)
        XCTAssertTrue(resolve(chinese + "ありがとう", selected: .simplifiedChinese, priority: japaneseFirst).switched)
    }

    func testLinksHandlesAndTagsAreLeftOut() {
        for text in ["今天的活动改到下午三点，详情请看 city.example.cn/winter",
                     "今天的活动改到下午三点，详情请看 https://example.com/events/2026?from=app",
                     "今天的活动改到下午三点，详情请看www.example.com",
                     "今天的活动改到下午三点，有问题请发邮件到 events@example.com",
                     "今天的活动改到下午三点 @city_events #WinterFestival"] {
            XCTAssertEqual(guess(text), .simplifiedChinese, text)
        }
        XCTAssertEqual(guess("Read the full story at news.example.com before the meeting."), .english)
        // An address alone says nothing.
        XCTAssertNil(guess("https://example.com/events"))
        XCTAssertNil(guess("@city_events"))
    }

    func testShortLinesCountOnlyWithoutLongerText() {
        let chat = "佐藤健\n今天上午9:12\n明日よろしくね！\n了解です！\n已读\n按住 说话"
        XCTAssertEqual(guess(chat), .japanese, "Next to a message, labels are the phone's")
        XCTAssertNil(guess(chat, .keyboard), "Typed text counts every character, as before")
        // Labels alone are all there is to go by.
        XCTAssertEqual(guess("コーヒー\n紅茶\nケーキ"), .japanese)
        XCTAssertEqual(guess("已读\n按住 说话"), .simplifiedChinese)
    }

    func testReadingAScreenStaysFast() {
        let screen = String(repeating: Self.japaneseTimeline + "\n", count: 10)
        let started = Date()
        for _ in 0..<50 { _ = guess(screen) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "The intent has a time limit")
    }
}
