import UIKit
import UniformTypeIdentifiers
import ImageIO

enum ClipboardInput {
    enum Content { case text(String), image(Data) }

    // PasteButton supplies only items the user explicitly chose to paste.
    // Never poll the pasteboard or open a copied URL as a network resource.
    static func load(_ providers: [NSItemProvider], imagesOnly: Bool) async throws -> Content {
        var offeredImage = false
        for provider in providers {
            let types = provider.registeredTypeIdentifiers.filter { UTType($0)?.conforms(to: .image) == true }
            guard !types.isEmpty || provider.canLoadObject(ofClass: UIImage.self) else { continue }
            offeredImage = true
            // Providers from Safari, Photos and the system clipboard do not all
            // vend the same representation. An advertised PNG can fail while
            // the UIImage or another encoded representation is still available.
            for type in types {
                try Task.checkCancellation()
                if let bytes = try? await data(from: provider, type: type), try validImage(bytes) {
                    return .image(bytes)
                }
                try Task.checkCancellation()
                if let bytes = try? await fileData(from: provider, type: type), try validImage(bytes) {
                    return .image(bytes)
                }
            }
            if provider.canLoadObject(ofClass: UIImage.self),
               let image = try? await image(from: provider),
               let bytes = image.pngData(), try validImage(bytes) {
                return .image(bytes)
            }
        }
        try Task.checkCancellation()
        // A broken image must not silently become its filename or URL.
        if offeredImage { throw TranslationError.clipboardImageUnavailable }
        if !imagesOnly {
            for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
                let value: String = try await withCheckedThrowingContinuation { continuation in
                    _ = provider.loadObject(ofClass: NSString.self) { object, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let text = object as? String { continuation.resume(returning: text) }
                        else { continuation.resume(throwing: TranslationError.emptyText) }
                    }
                }
                return .text(try TextPreparation.validated(value))
            }
        }
        throw imagesOnly ? TranslationError.imageRequired : TranslationError.emptyText
    }

    private static func validImage(_ data: Data) throws -> Bool {
        guard data.count <= 25 * 1_024 * 1_024 else { throw TranslationError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return false }
        guard width.doubleValue * height.doubleValue <= 100_000_000 else { throw TranslationError.imageTooLarge }
        return width.intValue > 0 && height.intValue > 0
    }

    private static func image(from provider: NSItemProvider) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? TranslationError.invalidImage) }
            }
        }
    }

    private static func fileData(from provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                do {
                    guard let url else { throw error ?? TranslationError.invalidImage }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 25 * 1_024 * 1_024 else { throw TranslationError.imageTooLarge }
                    // This temporary URL is valid only during the callback.
                    continuation.resume(returning: try Data(contentsOf: url))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func data(from provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: TranslationError.invalidImage) }
            }
        }
    }
}
