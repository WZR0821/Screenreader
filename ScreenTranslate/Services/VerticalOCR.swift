import Foundation
import CoreGraphics
import Vision

/// Reflow upright vertical glyph crops into horizontal strips for Vision.
/// Pixels are moved, not invented or rotated; original column boxes are retained.
enum VerticalOCR {
    private struct Column { var x: Range<Int>; var glyphs: [Range<Int>] }

    static func recognize(_ image: CGImage, forced: Bool, limit: Int) throws -> [RecognizedLine] {
        let scale = min(1, 2048 / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 255, count: width * height)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return [] }
        let mean = pixels.reduce(0.0) { $0 + Double($1) } / Double(pixels.count)
        let darkBackground = mean < 110
        let threshold = darkBackground ? max(155, mean + 45) : min(170, mean - 45)
        func ink(_ x: Int, _ y: Int) -> Bool {
            darkBackground ? Double(pixels[y * width + x]) > threshold : Double(pixels[y * width + x]) < threshold
        }
        var profile = [Int](repeating: 0, count: width)
        for y in 0..<height {
            if y % 100 == 0 { try Task.checkCancellation() }
            for x in 0..<width where ink(x, y) { profile[x] += 1 }
        }
        let bands = runs(profile.map { $0 >= max(4, height / 220) }, gap: 2)
        var columns: [Column] = []
        for band in bands where (7...max(8, min(150, width / 6))).contains(band.count) {
            var rows = [Bool](repeating: false, count: height)
            for y in 0..<height { rows[y] = band.reduce(0) { $0 + (ink($1, y) ? 1 : 0) } >= 2 }
            let glyphs = runs(rows, gap: max(2, band.count / 7)).filter { $0.count >= 2 }
            guard glyphs.count >= 4, glyphs.count <= 100,
                  glyphs.filter({ (Double(band.count) * 0.4...Double(band.count) * 1.65).contains(Double($0.count)) }).count >= glyphs.count * 3 / 4,
                  let first = glyphs.first, let last = glyphs.last,
                  last.upperBound - first.lowerBound > band.count * 4 else { continue }
            let gaps = zip(glyphs, glyphs.dropFirst()).map { $1.lowerBound - $0.upperBound }
            guard gaps.allSatisfy({ $0 < band.count * 2 }) else { continue }
            columns.append(.init(x: band, glyphs: glyphs))
        }
        guard forced || columns.count >= 2 else { return [] }
        var output: [RecognizedLine] = []
        for column in columns.sorted(by: { $0.x.lowerBound > $1.x.lowerBound }).prefix(limit) {
            try Task.checkCancellation()
            let cell = max(40, min(100, Int(Double(column.x.count) / scale) + 12))
            // Bounded strips prevent a long column from creating an enormous bitmap.
            var texts: [String] = [], confidence: Float = 1
            for offset in stride(from: 0, to: column.glyphs.count, by: 24) {
                let glyphs = Array(column.glyphs.dropFirst(offset).prefix(24))
                guard let context = CGContext(data: nil, width: cell * glyphs.count + 24, height: cell + 24,
                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
                context.setFillColor(gray: darkBackground ? 0 : 1, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
                for (index, glyph) in glyphs.enumerated() {
                    let rect = CGRect(x: Double(column.x.lowerBound) / scale, y: Double(glyph.lowerBound) / scale,
                        width: Double(column.x.count) / scale, height: Double(glyph.count) / scale).integral
                    guard let crop = image.cropping(to: rect) else { continue }
                    let ratio = min(Double(cell - 6) / Double(crop.width), Double(cell - 6) / Double(crop.height))
                    let w = Double(crop.width) * ratio, h = Double(crop.height) * ratio
                    context.draw(crop, in: CGRect(x: 12 + Double(index * cell) + (Double(cell) - w) / 2,
                        y: 12 + (Double(cell) - h) / 2, width: w, height: h))
                }
                guard let strip = context.makeImage() else { continue }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
                request.recognitionLanguages = ["ja-JP", "en-US"]; request.minimumTextHeight = 0.01
                try VNImageRequestHandler(cgImage: strip).perform([request])
                try Task.checkCancellation()
                let candidates = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }.compactMap { $0.topCandidates(1).first }
                guard !candidates.isEmpty else { texts = []; break }
                texts.append(candidates.map(\.string).joined())
                confidence = min(confidence, candidates.map(\.confidence).min() ?? 0)
            }
            let text = texts.joined().replacingOccurrences(of: " ", with: "")
            let cjk = text.unicodeScalars.filter { (0x3000...0x9FFF).contains($0.value) }.count
            guard text.count >= column.glyphs.count / 2, text.count <= column.glyphs.count * 2,
                  cjk >= 2, confidence >= 0.3,
                  let first = column.glyphs.first, let last = column.glyphs.last else { continue }
            output.append(.init(text: text, x: Double(column.x.lowerBound) / Double(width),
                y: 1 - Double(last.upperBound) / Double(height), width: Double(column.x.count) / Double(width),
                height: Double(last.upperBound - first.lowerBound) / Double(height), confidence: confidence,
                readingKind: .paragraph, vertical: true))
        }
        return output
    }

    private static func runs(_ values: [Bool], gap: Int) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start: Int?, last = 0
        for (index, active) in values.enumerated() where active {
            if let first = start, index - last - 1 > gap { result.append(first..<last + 1); start = index }
            else if start == nil { start = index }
            last = index
        }
        if let start { result.append(start..<last + 1) }
        return result
    }
}
