import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Apply EXIF orientation once, bound memory use, and remove camera metadata.
/// Used only for the current reader / self-contained shortcut document.
struct SourceImagePresentation: Sendable {
    let data: Data
    let width: Int
    let height: Int

    static func prepare(_ data: Data) -> SourceImagePresentation? {
        guard data.count <= 25 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0, width * height <= 100_000_000 else { return nil }
        let limit = max(width, height) / min(width, height) > 2.5 ? 8192 : 4096
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit
        ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return .init(data: output as Data, width: image.width, height: image.height)
    }
}
