import Foundation
import CoreGraphics
import ImageIO

/// Colours read from the screenshot itself. A translated label then sits on
/// the original background in the original text colour, instead of a white
/// or black patch whose edges show where every box is.
struct ImageOverlayPalette: Equatable, Sendable {
    var background: ThemeRGB
    var ink: ThemeRGB

    /// An sRGB copy of the screenshot, 8 bits per channel, top row first.
    struct Pixels: Equatable, Sendable {
        let id = UUID()
        let width: Int
        let height: Int
        fileprivate let bytes: [UInt8]

        /// Colours only need a few pixels per stroke, so long screenshots are
        /// reduced to about `maximumPixels` to bound memory.
        init?(image: CGImage, maximumPixels: Int = 4_000_000) {
            guard image.width > 0, image.height > 0, maximumPixels > 0,
                  let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            let scale = min(1, (Double(maximumPixels) / (Double(image.width) * Double(image.height))).squareRoot())
            let width = max(1, Int((Double(image.width) * scale).rounded()))
            let height = max(1, Int((Double(image.height) * scale).rounded()))
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
                context.interpolationQuality = .medium
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            self.width = width; self.height = height; self.bytes = bytes
        }

        /// Expects an upright image, such as `SourceImagePresentation.data`.
        init?(data: Data, maximumPixels: Int = 4_000_000) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            self.init(image: image, maximumPixels: maximumPixels)
        }

        static func == (lhs: Pixels, rhs: Pixels) -> Bool { lhs.id == rhs.id }

        fileprivate func color(_ x: Double, _ y: Double) -> RGB? {
            let column = Int(x.rounded(.down)), row = Int(y.rounded(.down))
            guard column >= 0, row >= 0, column < width, row < height else { return nil }
            let offset = (row * width + column) * 4
            return RGB(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
        }
    }

    fileprivate struct RGB {
        var red: Int, green: Int, blue: Int
        func distance(to other: RGB) -> Int {
            let r = red - other.red, g = green - other.green, b = blue - other.blue
            return r * r + g * g + b * b
        }
        var theme: ThemeRGB { .init(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }
    }

    /// - Parameters:
    ///   - box: the source text, normalised with Vision's bottom-left origin.
    ///   - line: one source line in the same units (height, or width for a
    ///     vertical column); sets how far outside the text the background is read.
    static func sample(_ pixels: Pixels, box: OCRTextBox, line: Double?, vertical: Bool) -> ImageOverlayPalette? {
        guard box.isValid else { return nil }
        let width = Double(pixels.width), height = Double(pixels.height)
        let left = box.x * width, right = (box.x + box.width) * width
        let top = (1 - box.y - box.height) * height, bottom = (1 - box.y) * height
        let across = vertical ? right - left : bottom - top
        let known = line.map { $0 * (vertical ? width : height) }.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let linePixels = min(across, known ?? 0.025 * max(width, height))

        // The background: the band the label's margin will cover, just
        // outside the text. Its most common colour ignores neighbouring glyphs.
        let near = max(1.5, linePixels * 0.05), far = max(near + 2, linePixels * 0.16)
        var ring: [RGB] = []
        for distance in [near, (near + far) / 2, far] {
            let x0 = left - distance, x1 = right + distance, y0 = top - distance, y1 = bottom + distance
            let span = x1 - x0, down = y1 - y0, perimeter = 2 * (span + down)
            let step = max(1, perimeter / 160)
            var position = 0.0
            while position < perimeter {
                let point: (Double, Double)
                if position < span { point = (x0 + position, y0) }
                else if position < span + down { point = (x1, y0 + position - span) }
                else if position < 2 * span + down { point = (x1 - (position - span - down), y1) }
                else { point = (x0, y1 - (position - 2 * span - down)) }
                if let color = pixels.color(point.0, point.1) { ring.append(color) }
                position += step
            }
        }
        guard ring.count >= 8, let background = dominant(ring) else { return nil }

        // The text: of the pixels inside the box, those clearly unlike the
        // background; their most common colour is the solid stroke colour.
        var inside: [RGB] = []
        let step = max(1, ((right - left) * (bottom - top) / 2_000).squareRoot())
        var y = top + step / 2
        while y < bottom {
            var x = left + step / 2
            while x < right {
                if let color = pixels.color(x, y) { inside.append(color) }
                x += step
            }
            y += step
        }
        let paper = background.theme
        let farthest = inside.map { $0.distance(to: background) }.max() ?? 0
        var ink = paper.foreground
        if farthest >= 48 * 48, let strokes = dominant(inside.filter { $0.distance(to: background) * 4 >= farthest }) {
            ink = strokes.theme
        }
        // Keep coloured text (links, buttons) unless it would be hard to read.
        if ink.contrast(with: paper) < 3 { ink = ink.accessible(on: paper) }
        return .init(background: paper, ink: ink)
    }

    /// The most common colour, then refined to the mean of everything close
    /// to it, so JPEG noise across a bin edge does not split a flat area.
    private static func dominant(_ samples: [RGB]) -> RGB? {
        guard !samples.isEmpty else { return nil }
        var bins: [Int: (count: Int, red: Int, green: Int, blue: Int)] = [:]
        for color in samples {
            let key = (color.red >> 3) << 10 | (color.green >> 3) << 5 | (color.blue >> 3)
            let value = bins[key] ?? (0, 0, 0, 0)
            bins[key] = (value.count + 1, value.red + color.red, value.green + color.green, value.blue + color.blue)
        }
        // Ties go to the lower key so the result never depends on hashing.
        guard let best = bins.max(by: { $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key })?.value
        else { return nil }
        let centre = RGB(red: best.red / best.count, green: best.green / best.count, blue: best.blue / best.count)
        let close = samples.filter { $0.distance(to: centre) <= 3 * 10 * 10 }
        guard !close.isEmpty else { return centre }
        return RGB(red: close.map(\.red).reduce(0, +) / close.count, green: close.map(\.green).reduce(0, +) / close.count,
                   blue: close.map(\.blue).reduce(0, +) / close.count)
    }
}
