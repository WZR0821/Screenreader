#if DEBUG
import Foundation
import SwiftUI
import UIKit

/// Deterministic UI-test transport. This code is excluded from Release builds.
enum DebugFixtures {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-test") }
    static var mode: String {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--fixture-error") ? "error" : "success"
    }

    @MainActor static func makeStore() -> SettingsStore {
        let suite = "ScreenTranslate.UITest"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        Task { await TranslationCache.shared.clear() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenTranslate.UITest")
        try? FileManager.default.removeItem(at: directory)
        let keychain = KeychainStore(service: suite)
        let store = SettingsStore(defaults: defaults, directory: directory, keychain: keychain)
        var settings = AppSettings()
        settings.target = .simplifiedChinese // Explicit fixture language; production defaults to English.
        if ProcessInfo.processInfo.arguments.contains("--fixture-defaults") { return store }
        settings.provider = .custom
        settings.configuration.baseURL = "https://fixture.invalid/v1"
        settings.configuration.model = "ui-test-model"
        settings.askModeInShortcuts = ProcessInfo.processInfo.arguments.contains("--fixture-askmode")
        if ProcessInfo.processInfo.arguments.contains("--fixture-layout") { settings.mode = .professional }
        if ProcessInfo.processInfo.arguments.contains("--fixture-japanese") {
            settings.mode = .professional; settings.source = .japanese
        }
        if ProcessInfo.processInfo.arguments.contains("--fixture-reader") {
            settings.reader = .init(textSize: .large, spacing: .relaxed, showOriginal: true)
            settings.appearance = .light; settings.accentTheme = .blue
        }
        if ProcessInfo.processInfo.arguments.contains("--fixture-reader-collapsed") { settings.reader.showOriginal = false }
        try? store.save(settings, keys: [AIProvider.custom.rawValue: "ui-test-key"])
        if ProcessInfo.processInfo.arguments.contains("--fixture-history") {
            for (original, translated) in [("Coffee is ready.", "咖啡煮好了。"), ("The train arrives at 10.", "列车十点到达。"), ("Open the window.", "请打开窗户。")] {
                try? store.record(TranslationResult(original: original, translated: translated,
                    sourceLanguages: "英语", target: "中文", engine: "UI fixture", elapsed: 0.2, mode: .quick))
            }
        }
        return store
    }

    static func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DebugFixtureURLProtocol.self]
        return APIClient(session: URLSession(configuration: configuration))
    }

    @MainActor static func image() -> Data {
        if ProcessInfo.processInfo.arguments.contains("--fixture-japanese") {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1800), format: format).pngData { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1800))
                func text(_ value: String, _ x: Double, _ y: Double, _ size: Double) {
                    (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black])
                }
                text("ランチメニュー", 50, 100, 48)
                text("いずれかを抜く場合、ソースなしになります。", 50, 200, 28)
                text("あらかじめご了承ください。", 50, 242, 28)
                text("税込価格", 50, 350, 32); text("1,100円", 650, 350, 32)
                text("ドリンク（必須選択）", 50, 500, 42)
                text("コーヒー / Coffee", 50, 630, 32); text("450円（税込）", 650, 630, 30)
                text("紅茶 / Tea", 50, 730, 32); text("400円（税込）", 650, 730, 30)
                text("数量", 50, 880, 32); text("1", 760, 880, 32)
                text("ご利用条件", 50, 1050, 42)
                text("会員のみ利用可能。", 50, 1150, 30)
                text("クーポンは併用できません。", 50, 1192, 30)
                text("カートに追加する", 50, 1510, 34)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--fixture-layout") {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1800), format: format).pngData { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1800))
                func text(_ value: String, _ x: Double, _ y: Double, _ size: Double) {
                    (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black])
                }
                text("Breakfast menu", 50, 100, 48)
                text("Freshly made every morning.", 50, 200, 30)
                text("Served until noon.", 50, 240, 30)
                text("Drinks", 50, 380, 44)
                text("Coffee", 50, 500, 32); text("450 yen", 680, 500, 32)
                text("Tea", 50, 610, 32); text("Orange juice", 50, 720, 32); text("Soda", 50, 830, 32)
                text("Quantity", 50, 960, 32); text("1", 760, 960, 32)
                text("Information", 50, 1100, 44)
                text("Order before 11:30.", 50, 1200, 30)
                text("Offer ends on 2026/10/06.", 50, 1240, 30)
                text("Add to cart", 50, 1520, 34)
            }
        }
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
            ("青いカップ / Blue cup" as NSString).draw(at: CGPoint(x: 40, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 34), .foregroundColor: UIColor.black])
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 180, y: 240, width: 200, height: 220))
        }
    }
}

private final class DebugFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = DebugFixtures.mode == "error" ? 401 : 200
        let text: String
        if request.url?.path.hasSuffix("/models") == true { text = #"{"data":[{"id":"ui-test-model"}]}"# }
        else {
            let body = requestBodyForFixture()
            let prompt = (body?["instructions"] as? String)
                ?? ((body?["messages"] as? [[String: Any]])?.first?["content"] as? String ?? "")
            var translated = prompt.contains("Translate every part into Japanese") || prompt.contains("scene in Japanese") ? "こんにちは、世界。これは確認用の翻訳です。"
                : prompt.contains("Translate every part into English") || prompt.contains("scene in English") ? "Hello, world. This is a verified translation."
                : "你好，世界。这是一次经过验证的翻译。"
            if prompt.contains("VISION MODE:") { translated = "蓝色杯子。\n\n画面大意：白色背景上放着一个蓝色杯子。" }
            if prompt.contains("VISION MODE:"), ProcessInfo.processInfo.arguments.contains("--fixture-japanese") {
                translated = "文字大意\n午餐菜单，套餐含税价1,100日元。\n• 咖啡：450日元（含税）\n• 红茶：400日元（含税）\n\n数量1。仅限会员使用，优惠券不可叠加。如需去除其中任一种配料，将不加酱汁。\n\n画面大意\n餐饮下单页面，可选择饮料和数量，然后加入购物车。"
            }
            if ProcessInfo.processInfo.arguments.contains("--fixture-long") {
                translated = (1...24).map { "第\($0)段。这是一段完整保留的译文，商品重量 16g，价格 ¥3,980，数字与标点需要保留。" }.joined(separator: "\n\n\n\n") + "\n\n全文结束：最后一段可以读到。"
            }
            if prompt.contains("PROFESSIONAL OUTPUT PROTOCOL") {
                let input = (body?["input"] as? String)
                    ?? ((body?["messages"] as? [[String: Any]])?.last?["content"] as? String ?? "")
                if let data = input.data(using: .utf8),
                   let document = try? JSONDecoder().decode(ProfessionalLayout.Document.self, from: data) {
                    let blocks = document.blocks.map { block -> ProfessionalLayout.Block in
                        var text = "\(translated)（第\(block.id)块）\n\(block.text)"
                        if ProcessInfo.processInfo.arguments.contains("--fixture-layout") {
                            text = block.text
                            for (source, target) in [("Breakfast menu", "早餐菜单"), ("Freshly made every morning.", "每天早上新鲜制作。"),
                                ("Served until noon.", "供应至中午。"), ("Drinks", "饮料"), ("Coffee", "咖啡"), ("450 yen", "450 日元"),
                                ("Tea", "茶"), ("Orange juice", "橙汁"), ("Soda", "苏打水"), ("Quantity", "数量"),
                                ("Information", "说明"), ("Order before 11:30.", "请在11:30前下单。"),
                                ("Offer ends on 2026/10/06.", "优惠截至2026/10/06。"), ("Add to cart", "加入购物车")] {
                                text = text.replacingOccurrences(of: source, with: target)
                            }
                        }
                        if ProcessInfo.processInfo.arguments.contains("--fixture-japanese") {
                            text = block.text
                            for (source, target) in [("ランチメニュー", "午餐菜单"), ("いずれかを抜く場合、ソースなしになります。", "如需去除其中任一种配料，将不加酱汁。"),
                                ("あらかじめご了承ください。", "敬请理解。"), ("税込価格", "含税价格"), ("ドリンク", "饮料"),
                                ("必須選択", "必选"), ("コーヒー", "咖啡"), ("紅茶", "红茶"), ("税込", "含税"), ("円", "日元"),
                                ("/ Coffee", ""), ("/Coffee", ""), ("/ Tea", ""), ("/Tea", ""),
                                ("ご利用条件", "使用条件"), ("会員のみ利用可能。", "仅限会员使用。"),
                                ("クーポンは併用できません。", "优惠券不可叠加。"), ("カートに追加する", "加入购物车")] {
                                text = text.replacingOccurrences(of: source, with: target)
                            }
                        }
                        return ProfessionalLayout.Block(id: block.id, text: text)
                    }
                    translated = String(decoding: try! JSONEncoder().encode(ProfessionalLayout.Document(blocks: blocks)), as: UTF8.self)
                }
            }
            let data = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": translated], "finish_reason": "stop"]]])
            text = String(decoding: data, as: UTF8.self)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private func requestBodyForFixture() -> [String: Any]? {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
#endif
