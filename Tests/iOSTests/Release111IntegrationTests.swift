import XCTest
import UIKit
import UniformTypeIdentifiers
@testable import ScreenTranslate

@MainActor
final class Release111IntegrationTests: XCTestCase {
    func testClipboardRecoversWhenFirstAdvertisedImageRepresentationFails() async throws {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(nil, NSError(domain: NSItemProvider.errorDomain, code: -1000)); return nil
        }
        let expected = UIImage(data: DebugFixtures.image())!.jpegData(compressionQuality: 0.9)!
        provider.registerDataRepresentation(forTypeIdentifier: UTType.jpeg.identifier, visibility: .all) { completion in
            completion(expected, nil); return nil
        }
        let result = try await ClipboardInput.load([provider], imagesOnly: true)
        guard case .image(let actual) = result else { return XCTFail("Expected image") }
        XCTAssertEqual(actual, expected)
    }

    func testClipboardFileRepresentationIsConsumedBeforeTemporaryFileExpires() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-\(UUID()).png")
        let expected = DebugFixtures.image()
        try expected.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil); return nil
        }
        let result = try await ClipboardInput.load([provider], imagesOnly: true)
        guard case .image(let actual) = result else { return XCTFail("Expected image") }
        XCTAssertEqual(actual, expected)
    }

    func testBrokenImageDoesNotSilentlyPasteItsURLOrLeakProviderError() async throws {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(Data("not an image".utf8), nil); return nil
        }
        do {
            _ = try await ClipboardInput.load([provider, NSItemProvider(object: "https://example.test/image.png" as NSString)], imagesOnly: false)
            XCTFail("Expected a recoverable image error")
        } catch {
            XCTAssertEqual(error as? TranslationError, .clipboardImageUnavailable)
        }
    }
}
