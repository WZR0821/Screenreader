import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import ScreenTranslate

@MainActor
final class TranslationReviewIntegrationTests: XCTestCase {
    private func makeStore() throws -> SettingsStore {
        let suite = "ScreenTranslate.ReviewTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let keychain = KeychainStore(service: suite)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? keychain.write("", provider: .custom)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = SettingsStore(defaults: defaults, directory: directory, keychain: keychain)
        var settings = AppSettings(); settings.provider = .custom; settings.mode = .professional
        settings.target = .simplifiedChinese; settings.cacheTranslations = false
        settings.configuration.baseURL = "https://mock.test/v1"; settings.configuration.model = "review-fixture"
        try store.save(settings, keys: [AIProvider.custom.rawValue: "fixture-key"])
        return store
    }
    private func result() -> TranslationResult {
        let blocks: [ReadingBlock] = [
            .init(id: 1, text: "菜单", kind: .heading, original: "Menu"),
            .init(id: 2, text: "咖啡 450日元", kind: .field, original: "Coffee 450 yen",
                  sourceBox: .init(x: 0.1, y: 0.3, width: 0.8, height: 0.1)),
            .init(id: 3, text: "不可退款。", kind: .paragraph, original: "No refunds.")]
        return .init(original: blocks.compactMap(\.original).joined(separator: "\n\n"), translated: blocks.map(\.text).joined(separator: "\n\n"),
            sourceLanguages: "英语", target: "中文", engine: "fixture", elapsed: 1, mode: .professional, blocks: blocks)
    }
    private func pipeline() -> (TranslationPipeline, URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        addTeardownBlock { session.invalidateAndCancel(); StubURLProtocol.registry.set(nil) }
        return (TranslationPipeline(client: APIClient(session: session)), session)
    }
    private nonisolated static func response(_ texts: [ProfessionalLayout.Block]) throws -> (Int, Data) {
        let output = String(decoding: try JSONEncoder().encode(ProfessionalLayout.Document(blocks: texts)), as: UTF8.self)
        return (200, try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": output], "finish_reason": "stop"]]]))
    }
    private nonisolated static func input(_ request: URLRequest) throws -> (String, ProfessionalLayout.Document) {
        let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
        let messages = body["messages"] as! [[String: Any]]
        let text = messages.last!["content"] as! String
        return (messages.first!["content"] as! String, try JSONDecoder().decode(ProfessionalLayout.Document.self, from: Data(text.utf8)))
    }
    private func waitUntilIdle(_ model: TranslationBlockReviewModel) async throws {
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(model.busy)
    }

    func testOnlySelectedSourceIsSentAndHistoricalTargetIsKept() async throws {
        let (pipeline, _) = pipeline()
        let before = result()
        let counter = RequestCounter()
        StubURLProtocol.registry.set { request in
            counter.increment()
            let (prompt, document) = try Self.input(request)
            XCTAssertTrue(prompt.contains("Simplified Chinese")); XCTAssertFalse(prompt.contains("Translate every part into Japanese"))
            XCTAssertEqual(document.blocks.count, 1); XCTAssertEqual(document.blocks[0].id, 1)
            XCTAssertEqual(document.blocks[0].text, "Coffee 460 yen"); XCTAssertEqual(document.blocks[0].kind, .field)
            XCTAssertFalse(String(decoding: requestBody(request), as: UTF8.self).contains("sourceBox"))
            return try Self.response([.init(id: 1, text: "咖啡 460日元")])
        }
        var settings = AppSettings(); settings.provider = .custom; settings.target = .japanese
        settings.configuration.baseURL = "https://mock.test/v1"; settings.configuration.model = "review-fixture"
        let block = try await pipeline.retranslateBlock(in: before, blockID: 2, correctedText: "Coffee 460 yen", settings: settings, key: "fixture-key")
        XCTAssertEqual(block.id, 2); XCTAssertEqual(block.original, "Coffee 460 yen")
        XCTAssertEqual(block.sourceBox, before.blocks?[1].sourceBox)
        XCTAssertNotNil(block.reviewEngine); XCTAssertEqual(counter.value, 1)
        _ = try await pipeline.retranslateBlock(in: before, blockID: 2, correctedText: "Coffee 460 yen", settings: settings, key: "fixture-key")
        XCTAssertEqual(counter.value, 2, "Explicit paragraph retranslation must request fresh output")
        let updated = try TranslationReview.replacing(in: before, blockID: 2, with: block)
        XCTAssertEqual(updated.blocks?[0], before.blocks?[0]); XCTAssertEqual(updated.blocks?[2], before.blocks?[2])
    }

    func testCorrectedSourceIsUsedForNextWholeTranslationAndManualEditsClearMapping() async throws {
        let store = try makeStore()
        let (pipeline, _) = pipeline()
        let counter = RequestCounter()
        StubURLProtocol.registry.set { request in
            counter.increment()
            let (_, document) = try Self.input(request)
            if counter.value == 3 {
                XCTAssertEqual(document.blocks.count, 3)
                XCTAssertTrue(document.blocks.contains { $0.text == "Coffee 460 yen" })
                XCTAssertFalse(document.blocks.contains { $0.text.contains("450") })
            }
            return try Self.response(document.blocks.map { block in
                let value = block.text.replacingOccurrences(of: "Menu", with: "菜单")
                    .replacingOccurrences(of: "Coffee", with: "咖啡").replacingOccurrences(of: "yen", with: "日元")
                    .replacingOccurrences(of: "No refunds.", with: "不可退款。")
                return .init(id: block.id, text: value)
            })
        }
        let model = TranslationViewModel(store: store, pipeline: pipeline)
        try model.acceptImage(DebugFixtures.image())
        model.text = "Menu\n\nCoffee 450 yen\n\nNo refunds."
        model.translate()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 20_000_000) }
        let before = try XCTUnwrap(model.result)
        let block = try await pipeline.retranslateBlock(in: before, blockID: 2, correctedText: "Coffee 460 yen", settings: store.settings, key: "fixture-key")
        let updated = try TranslationReview.replacing(in: before, blockID: 2, with: block)
        try model.applyBlockReview(updated, expected: before)
        XCTAssertEqual(model.result, updated); XCTAssertEqual(model.text, updated.original)
        XCTAssertEqual(store.history.count, 1); XCTAssertEqual(store.history.first, updated)
        XCTAssertNil(model.recognizedOCR)
        model.modeChanged()
        XCTAssertTrue(model.text.contains("460"))
        model.translate()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(model.result?.translated.contains("460") == true)
        XCTAssertEqual(counter.value, 3)
        // Editing the same result from history must also refresh the active editor.
        let active = try XCTUnwrap(model.result)
        let historicalBlock = try await pipeline.retranslateBlock(in: active, blockID: 2, correctedText: "Coffee 480 yen", settings: store.settings, key: "fixture-key")
        let historicalEdit = try TranslationReview.replacing(in: active, blockID: 2, with: historicalBlock)
        XCTAssertTrue(try store.replaceRecordedResult(active, with: historicalEdit))
        model.refreshReviewedResult()
        XCTAssertEqual(model.result, historicalEdit); XCTAssertTrue(model.text.contains("480"))
        XCTAssertThrowsError(try model.applyBlockReview(updated, expected: before))
        model.resetRecognition()
        XCTAssertTrue(model.text.contains("480"), "An attached image must not turn reviewed manual text into automatic OCR")
        model.text = "A different document."
        model.refreshReviewedResult()
        XCTAssertNil(model.result)
    }

    func testCancelledBlockRequestCannotCommitOrChangeHistory() async throws {
        let store = try makeStore()
        let before = result(); try store.record(before)
        let (pipeline, _) = pipeline()
        let started = RequestCounter()
        StubURLProtocol.registry.set { _ in
            started.increment()
            Thread.sleep(forTimeInterval: 0.15)
            return try Self.response([.init(id: 1, text: "咖啡 460日元")])
        }
        let model = TranslationBlockReviewModel(selection: .init(result: before, blockID: 2), imageData: nil, pipeline: pipeline)
        model.drafts = ["Coffee 460 yen"]
        model.retranslate(using: store) { _, _ in XCTFail("A cancelled request must never commit") }
        for _ in 0..<50 where started.value == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(started.value, 1); XCTAssertTrue(model.busy)
        model.cancel()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertFalse(model.busy); XCTAssertFalse(model.completed)
        XCTAssertEqual(store.history.first, before); XCTAssertEqual(model.selection.result, before)
    }

    func testNetworkFailureAndIncompleteOutputKeepOriginalResultAndDraft() async throws {
        let store = try makeStore()
        let before = result(); try store.record(before)
        let (pipeline, _) = pipeline()
        for incomplete in [false, true] {
            StubURLProtocol.registry.set { _ in
                incomplete ? try Self.response([.init(id: 1, text: "咖啡 450日元")]) : (401, Data())
            }
            let model = TranslationBlockReviewModel(selection: .init(result: before, blockID: 2), imageData: nil, pipeline: pipeline)
            model.drafts = ["Coffee 460 yen"]
            model.retranslate(using: store) { _, _ in XCTFail("A failed request must never commit") }
            try await waitUntilIdle(model)
            XCTAssertNotNil(model.error); XCTAssertFalse(model.completed)
            XCTAssertEqual(model.correctedText, "Coffee 460 yen")
            XCTAssertEqual(store.history.first, before)
        }
    }

    func testHistoryRevisionDoesNotDuplicateReorderOrReviveDeletedRecord() throws {
        let store = try makeStore()
        let before = result(); try store.record(before)
        var newer = result(); newer.original = "Another record"; try store.record(newer)
        var updated = before; updated.warning = "reviewed"
        XCTAssertTrue(try store.replaceRecordedResult(before, with: updated))
        XCTAssertEqual(store.history.map(\.id), [newer.id, before.id]); XCTAssertEqual(store.history.count, 2)
        XCTAssertThrowsError(try store.replaceRecordedResult(before, with: updated)) {
            XCTAssertEqual($0 as? TranslationError, .reviewConflict)
        }
        try store.deleteResult(before.id)
        XCTAssertFalse(try store.replaceRecordedResult(updated, with: before))
        XCTAssertEqual(store.history.map(\.id), [newer.id])
        var settings = store.settings; settings.saveRecentResult = false
        try store.save(settings, keys: [:])
        XCTAssertFalse(try store.replaceRecordedResult(newer, with: newer)); XCTAssertTrue(store.history.isEmpty)
    }

    func testCropsUseBottomLeftCoordinatesAndApplyEXIFOrientation() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 120), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 200, height: 60))
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 60, width: 200, height: 60))
        }
        let png = try XCTUnwrap(image.pngData())
        let bottom = try XCTUnwrap(SourceImageCrop.png(png, box: .init(x: 0.2, y: 0.05, width: 0.5, height: 0.2)))
        XCTAssertGreaterThan(centerPixel(bottom)[2], 230); XCTAssertLessThan(centerPixel(bottom)[0], 20)
        let rotatedData = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(rotatedData, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image.cgImage!, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let left = try XCTUnwrap(SourceImageCrop.png(rotatedData as Data, box: .init(x: 0.05, y: 0.1, width: 0.25, height: 0.8)))
        XCTAssertGreaterThan(centerPixel(left)[2], 220); XCTAssertLessThan(centerPixel(left)[0], 30)
        XCTAssertNil(SourceImageCrop.png(png, box: .init(x: 4, y: 4, width: 0.1, height: 0.1)))
        XCTAssertNil(SourceImageCrop.png(png, box: .init(x: .nan, y: 0, width: 1, height: 1)))
    }
    private func centerPixel(_ data: Data) -> [UInt8] {
        let image = UIImage(data: data)!.cgImage!
        let center = image.cropping(to: CGRect(x: image.width / 2, y: image.height / 2, width: 1, height: 1))!
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(center, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel
    }

    func testRealVisionBlockCanBeLocatedAndCroppedWithoutSavingImageToHistory() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600), format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
            ("Menu" as NSString).draw(at: CGPoint(x: 60, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 50), .foregroundColor: UIColor.black])
            ("Coffee 450 yen" as NSString).draw(at: CGPoint(x: 60, y: 250), withAttributes: [.font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.black])
        }
        let recognized = try await OCRService().recognize(data, source: .english, mode: .professional)
        let block = try XCTUnwrap(recognized.blocks.first { $0.text.contains("450") })
        let bounds = try XCTUnwrap(block.sourceBox)
        let crop = try XCTUnwrap(SourceImageCrop.png(data, box: bounds))
        let croppedOCR = try await OCRService().recognize(crop, source: .english)
        XCTAssertTrue(croppedOCR.text.contains("450")); XCTAssertFalse(croppedOCR.text.contains("Menu"))
        let encoded = try JSONEncoder().encode(result())
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("imageData"))
        XCTAssertLessThan(encoded.count, 4000)
        let attachment = XCTAttachment(data: crop, uniformTypeIdentifier: UTType.png.identifier)
        attachment.name = "译文核对原图区域-Vision"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testLongScreenshotReviewKeepsTheOCRResolutionForSmallPrint() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 10000), format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 10000))
            ("Small print 19" as NSString).draw(at: CGPoint(x: 100, y: 5000), withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.black])
        }
        let crop = try XCTUnwrap(SourceImageCrop.png(data, box: .init(x: 0.1, y: 0.49, width: 0.8, height: 0.015)))
        XCTAssertGreaterThan(try XCTUnwrap(UIImage(data: crop)?.cgImage).width, 580)
    }

    func testStaleEditorCannotOverwriteAnotherRevision() async throws {
        let store = try makeStore()
        let before = result(); try store.record(before)
        let (pipeline, _) = pipeline()
        StubURLProtocol.registry.set { _ in try Self.response([.init(id: 1, text: "咖啡 460日元")]) }
        var another = before; another.warning = "another revision"
        try store.replaceRecordedResult(before, with: another)
        let model = TranslationBlockReviewModel(selection: .init(result: before, blockID: 2), imageData: nil, pipeline: pipeline)
        model.drafts = ["Coffee 460 yen"]
        model.retranslate(using: store) { expected, updated in
            guard try store.replaceRecordedResult(expected, with: updated) else { throw TranslationError.reviewConflict }
        }
        try await waitUntilIdle(model)
        XCTAssertEqual(model.error, TranslationError.reviewConflict.localizedDescription)
        XCTAssertFalse(model.completed); XCTAssertEqual(store.history.first, another)
    }
}
