import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SourceImageCrop {
    /// Vision coordinates use a bottom-left origin in the oriented image.
    static func png(_ data: Data, box: OCRTextBox) -> Data? {
        guard box.isValid,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0, width * height <= 100_000_000 else { return nil }
        // Match the OCR resolution for long screenshots, so small print doesn't
        // become less legible when the user opens its verification crop.
        let maximumPixels = max(width, height) / min(width, height) > 2.5 ? 8192 : 4096
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixels
              ] as CFDictionary) else { return nil }
        let w = Double(image.width), h = Double(image.height)
        let left = max(0, box.x), bottom = max(0, box.y)
        let right = min(1, box.x + box.width), top = min(1, box.y + box.height)
        guard right > left, top > bottom else { return nil }
        let rect = CGRect(x: left * w, y: (1 - top) * h, width: (right - left) * w, height: (top - bottom) * h)
            .insetBy(dx: -12, dy: -12).intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard !rect.isNull, !rect.isEmpty, let crop = image.cropping(to: rect) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, crop, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
