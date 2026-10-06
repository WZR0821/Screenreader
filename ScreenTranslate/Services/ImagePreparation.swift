import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

struct PreparedVisionImage {
    var overview: Data
    var details: [Data]
}

enum ImagePreparation {
    /// Keep an overview for context and two overlapping detail crops for small
    /// text on tall screenshots. All frames are from one image, with no EXIF.
    static func vision(_ data: Data) async throws -> PreparedVisionImage {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard data.count <= 25 * 1_024 * 1_024 else { throw TranslationError.imageTooLarge }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue * height.doubleValue <= 100_000_000,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 3_072
                  ] as CFDictionary) else { throw TranslationError.invalidImage }
            let overview = try encode(image, maximumDimension: 2_048)
            var details: [Data] = []
            let long = max(image.width, image.height), short = min(image.width, image.height)
            if long > 2_048 && Double(long) / Double(max(1, short)) >= 1.6 {
                for start in [0.0, 0.44] {
                    try Task.checkCancellation()
                    let rect = image.height >= image.width
                        ? CGRect(x: 0, y: start * Double(image.height), width: Double(image.width), height: 0.56 * Double(image.height))
                        : CGRect(x: start * Double(image.width), y: 0, width: 0.56 * Double(image.width), height: Double(image.height))
                    guard let crop = image.cropping(to: rect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))) else {
                        throw TranslationError.invalidImage
                    }
                    details.append(try encode(crop, maximumDimension: 1_800))
                }
            }
            guard overview.count + details.reduce(0, { $0 + $1.count }) <= 8 * 1_024 * 1_024 else { throw TranslationError.imageTooLarge }
            try Task.checkCancellation()
            return PreparedVisionImage(overview: overview, details: details)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private static func encode(_ image: CGImage, maximumDimension: Int) throws -> Data {
        var resized = image
        let scale = min(1.0, Double(maximumDimension) / Double(max(image.width, image.height)))
        if scale < 1 {
            guard let context = CGContext(data: nil, width: max(1, Int(Double(image.width) * scale)),
                height: max(1, Int(Double(image.height) * scale)), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw TranslationError.invalidImage }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
            guard let output = context.makeImage() else { throw TranslationError.invalidImage }
            resized = output
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw TranslationError.invalidImage }
        CGImageDestinationAddImage(destination, resized, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw TranslationError.invalidImage }
        return output as Data
    }

    /// Decode off the UI thread, apply EXIF orientation, resize and re-encode.
    /// The new JPEG carries pixels only, not the original GPS/EXIF metadata.
    static func jpeg(_ data: Data) async throws -> Data {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard data.count <= 25 * 1_024 * 1_024 else { throw TranslationError.imageTooLarge }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = props[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue * height.doubleValue <= 100_000_000,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2_048
                  ] as CFDictionary) else { throw TranslationError.invalidImage }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw TranslationError.invalidImage
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw TranslationError.invalidImage }
            try Task.checkCancellation()
            return output as Data
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
