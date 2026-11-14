import XCTest
import UIKit
@testable import ScreenTranslate

/// 1.3.3: without 原图直译 a quick screenshot goes out as plain text, as it
/// did before 1.3.0; the numbered blocks are only sent when something uses them.
final class Release133IntegrationTests: XCTestCase {
    private static func menu() -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1100), format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 1100))
            let lines = ["Breakfast menu", "Freshly made every morning.", "Coffee 450 yen", "Tea 400 yen",
                         "Orange juice 500 yen", "Quantity 1", "Order before 11:30.", "Add to cart"]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 50, y: 80 + index * 120),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.black])
            }
        }
    }

    private final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [(request: Int, reply: Int, blocks: Bool)] = []
        func append(_ value: (request: Int, reply: Int, blocks: Bool)) { lock.lock(); values.append(value); lock.unlock() }
        var all: [(request: Int, reply: Int, blocks: Bool)] { lock.lock(); defer { lock.unlock() }; return values }
    }

    func testQuickScreenshotSendsPlainTextUnlessImageOverlayIsOn() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        let requests = Requests()
        StubURLProtocol.registry.set { request in
            let body = requestBody(request)
            let root = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            let system = (root["messages"] as! [[String: Any]])[0]["content"] as! String
            let reply = try imageLayoutResponse(request) {
                $0.replacingOccurrences(of: "Breakfast menu", with: "早餐菜单").replacingOccurrences(of: "Coffee", with: "咖啡")
                    .replacingOccurrences(of: "Tea", with: "茶").replacingOccurrences(of: "yen", with: "日元")
            }
            requests.append((body.count, reply.1.count, system.contains("PROFESSIONAL OUTPUT PROTOCOL")))
            return reply
        }
        var settings = AppSettings(); settings.provider = .custom; settings.source = .english; settings.cacheTranslations = false
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "fixture"
        XCTAssertFalse(TranslationPipeline.sendsBlocks(settings))
        let pipeline = TranslationPipeline(client: APIClient(session: session))
        let plain = try await pipeline.image(Self.menu(), settings: settings, key: "fixture-key")
        XCTAssertNil(plain.blocks)
        XCTAssertTrue(ImageTranslationLayout.items(in: plain).isEmpty)
        XCTAssertTrue(plain.translated.contains("咖啡") && plain.translated.contains("450"))

        settings.imageOverlay = true
        XCTAssertTrue(TranslationPipeline.sendsBlocks(settings))
        let overlay = try await pipeline.image(Self.menu(), settings: settings, key: "fixture-key")
        XCTAssertFalse(ImageTranslationLayout.items(in: overlay).isEmpty)
        XCTAssertTrue(overlay.blocks!.allSatisfy { $0.sourceBox?.isValid == true })

        let sent = requests.all
        XCTAssertEqual(sent.map(\.blocks), [false, true])
        XCTAssertLessThan(sent[0].request, sent[1].request)
        XCTAssertLessThan(sent[0].reply, sent[1].reply)
        let log = #"{"plainRequestBytes":\#(sent[0].request),"overlayRequestBytes":\#(sent[1].request),"plainReplyBytes":\#(sent[0].reply),"overlayReplyBytes":\#(sent[1].reply)}"#
        print("RELEASE133_SIZES " + log)
        let attachment = XCTAttachment(string: log); attachment.name = "1.3.3-request-size"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testOnlyProfessionalModeOrImageOverlaySendsBlocks() {
        var settings = AppSettings()
        for mode in [TranslationMode.quick, .professional] {
            for overlay in [false, true] {
                settings.mode = mode; settings.imageOverlay = overlay
                XCTAssertEqual(TranslationPipeline.sendsBlocks(settings), mode == .professional || overlay, "\(mode) \(overlay)")
            }
        }
    }

    /// 原图直译 turned on after a plain quick result: the main button sends the
    /// same screenshot again, this time with blocks, and only once.
    @MainActor func testImageOverlayTurnedOnLaterTranslatesTheSameScreenshotOnce() async throws {
        let suite = "ScreenTranslate.Release133.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainStore(service: suite)
        defer { defaults.removePersistentDomain(forName: suite); try? keychain.write("", provider: .custom) }
        let store = SettingsStore(defaults: defaults, keychain: keychain)
        var settings = AppSettings(); settings.provider = .custom; settings.source = .english
        settings.saveRecentResult = false; settings.cacheTranslations = false
        settings.configuration.baseURL = "https://mock.test/v1"; settings.configuration.model = "fixture"
        try store.save(settings, keys: [AIProvider.custom.rawValue: "fixture-key"])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        let requests = Requests()
        StubURLProtocol.registry.set { request in
            let root = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            let system = (root["messages"] as! [[String: Any]])[0]["content"] as! String
            requests.append((0, 0, system.contains("PROFESSIONAL OUTPUT PROTOCOL")))
            return try imageLayoutResponse(request) { $0.replacingOccurrences(of: "Breakfast menu", with: "早餐菜单") }
        }
        let model = TranslationViewModel(store: store, pipeline: TranslationPipeline(client: APIClient(session: session)))
        try model.acceptImage(Self.menu())
        model.translate()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertNil(model.error)
        XCTAssertNil(try XCTUnwrap(model.result).blocks)
        XCTAssertFalse(model.needsImageTranslation(store.settings), "With 原图直译 off the button reopens the text")

        settings = store.settings; settings.imageOverlay = true
        try store.save(settings, keys: [:])
        XCTAssertTrue(model.needsImageTranslation(store.settings))
        model.translate()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertNil(model.error)
        let placed = try XCTUnwrap(model.result)
        XCTAssertFalse(ImageTranslationLayout.items(in: placed).isEmpty)
        XCTAssertTrue(placed.translated.contains("早餐菜单"))
        XCTAssertFalse(model.needsImageTranslation(store.settings), "A result with positions is reopened, so this cannot repeat")
        XCTAssertEqual(requests.all.map(\.blocks), [false, true], "The second request reused the on-screen OCR with its blocks")

        // Edited text has no positions left; the button translates as usual.
        model.text += " Updated."
        XCTAssertFalse(model.needsImageTranslation(store.settings))
    }
}
