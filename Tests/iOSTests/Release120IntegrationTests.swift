import XCTest
import UIKit
@testable import ScreenTranslate

final class Release120IntegrationTests: XCTestCase {
    func testRecognitionIdentityChangesWithEveryRecognitionInput() throws {
        let data = Data("image-content".utf8)
        func key(_ data: Data = data, source: SourceLanguage = .english, words: [String] = [],
                 clean: Bool = true, mode: TranslationMode = .quick, direction: OCRTextDirection = .automatic) throws -> String {
            try OCRCache.key(data: data, source: source, customWords: words, cleanScreenText: clean, mode: mode, direction: direction)
        }
        let original = try key()
        for other in try [key(Data("other-image".utf8)), key(source: .japanese), key(words: ["custom"]),
                          key(clean: false), key(mode: .professional), key(direction: .vertical)] {
            XCTAssertNotEqual(original, other)
        }
        XCTAssertEqual(original.count, 64)
        XCTAssertFalse(original.contains("image-content"))
    }

    func testRecognitionCacheEvictsExpiresAndCannotRepopulateAfterClear() async throws {
        let cache = OCRCache(capacity: 2, lifetime: 10)
        let value = OCRResult(text: "Coffee", languages: "英语", lowConfidence: false,
            blocks: [.init(id: 1, text: "Coffee", kind: .heading)], recognitionSeconds: 2, refinementSeconds: 1)
        let generation = await cache.generationToken()
        await cache.insert(value, for: "one", generation: generation, now: 1)
        await cache.insert(value, for: "two", generation: generation, now: 2)
        let hit = await cache.value(for: "one", now: 3)
        XCTAssertEqual(hit?.blocks, value.blocks)
        XCTAssertEqual(hit?.usedCache, true); XCTAssertEqual(hit?.recognitionSeconds, 0); XCTAssertEqual(hit?.refinementSeconds, 0)
        await cache.insert(value, for: "three", generation: generation, now: 4)
        let evicted = await cache.value(for: "two", now: 4)
        XCTAssertNil(evicted)
        let expired = await cache.value(for: "one", now: 12)
        XCTAssertNil(expired)
        await cache.clear()
        await cache.insert(value, for: "late", generation: generation, now: 13)
        let empty = await cache.statistics(now: 13)
        XCTAssertEqual(empty.count, 0); XCTAssertEqual(empty.hits, 0)
        let tiny = OCRCache(byteLimit: 1)
        await tiny.insert(value, for: "large", generation: 0)
        let tooLarge = await tiny.statistics()
        XCTAssertEqual(tooLarge.count, 0)
    }

    @MainActor func testRepeatedImageSkipsVisionAndNetworkAndDisablingCacheRunsBoth() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 650), format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 650))
            for (index, line) in ["Coffee menu", "Freshly made every morning.", "Coffee 450 yen", "Tea 300 yen"].enumerated() {
                (line as NSString).draw(at: CGPoint(x: 50, y: 90 + index * 90),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.black])
            }
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        let counter = RequestCounter()
        StubURLProtocol.registry.set { request in
            counter.increment()
            return try imageLayoutResponse(request) { $0.replacingOccurrences(of: "Coffee", with: "咖啡")
                .replacingOccurrences(of: "Tea", with: "茶").replacingOccurrences(of: "yen", with: "日元") }
        }
        var settings = AppSettings(); settings.provider = .custom; settings.source = .english
        settings.configuration.baseURL = "https://mock.test"; settings.configuration.model = "fixture"
        let pipeline = TranslationPipeline(client: APIClient(session: session))
        let first = try await pipeline.image(image, settings: settings, key: "fixture-key")
        let repeated = try await pipeline.image(image, settings: settings, key: "fixture-key")
        XCTAssertEqual(first.original, repeated.original); XCTAssertEqual(first.translated, repeated.translated)
        XCTAssertTrue(first.original.contains("450")); XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(repeated.usedCache, true)
        let stats = await pipeline.ocrCache.statistics()
        XCTAssertEqual(stats.count, 1); XCTAssertEqual(stats.hits, 1)
        settings.target = .japanese
        let changedTarget = try await pipeline.recognize(image, settings: settings)
        XCTAssertTrue(changedTarget.usedCache)
        XCTAssertFalse(changedTarget.blocks.isEmpty)
        settings.target = .simplifiedChinese; settings.cacheTranslations = false
        let uncached = try await pipeline.image(image, settings: settings, key: "fixture-key")
        XCTAssertEqual(uncached.usedCache, false); XCTAssertEqual(counter.value, 2)
        let after = await pipeline.ocrCache.statistics()
        XCTAssertEqual(after.hits, 2, "Disabling the cache must skip recognition lookup too")
        let log = """
        {"scenario":"real Vision, local HTTP stub (no external network)","firstSeconds":\(first.elapsed),"repeatSeconds":\(repeated.elapsed),"uncachedSeconds":\(uncached.elapsed),"firstOCRSeconds":\(first.recognitionSeconds ?? 0),"repeatOCRSeconds":\(repeated.recognitionSeconds ?? 0),"networkCallsForFirstAndRepeat":1}
        """
        print("RELEASE120_SPEED " + log)
        let attachment = XCTAttachment(string: log); attachment.name = "1.2.0-recognition-speed"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
