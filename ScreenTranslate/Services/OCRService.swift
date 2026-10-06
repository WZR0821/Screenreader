import Foundation
import Vision
import ImageIO
import NaturalLanguage
import CoreGraphics
import CoreImage

struct OCRResult {
    var text: String
    var languages: String
    var lowConfidence: Bool
    var rawText: String = ""
    var filteredLineCount: Int = 0
    var blocks: [ReadingBlock] = []
    var refinementAttempts: Int = 0
    var recoveredLineCount: Int = 0
}

struct OCRService {
    func recognize(_ data: Data, source: SourceLanguage = .automatic, customWords: [String] = [], cleanScreenText: Bool = true, mode: TranslationMode = .professional) async throws -> OCRResult {
        guard data.count <= 25 * 1_024 * 1_024 else { throw TranslationError.imageTooLarge }
        // Vision is synchronous; keep it off the UI and App Intent presentation thread.
        let worker = Task.detached(priority: .userInitiated) { try Self.recognizeSynchronously(data, source: source, customWords: customWords, cleanScreenText: cleanScreenText, mode: mode) }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }

    static func recognizeSynchronously(_ data: Data, source language: SourceLanguage = .automatic, customWords: [String] = [], cleanScreenText: Bool = true, mode: TranslationMode = .professional) throws -> OCRResult {
        try Task.checkCancellation()
        let japaneseWords = language == .japanese || language == .automatic ? JapaneseText.recognitionWords : []
        // User terminology has priority. These are exact Japanese UI/menu terms,
        // not substitutions for visually ambiguous characters or numbers.
        let recognitionWords = Array((customWords + japaneseWords).prefix(100))
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue * height.doubleValue <= 100_000_000 else {
            throw TranslationError.invalidImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: height.doubleValue / max(width.doubleValue, 1) > 2.5 ? 8_192 : (mode == .quick ? 2_560 : 4_096),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw TranslationError.invalidImage
        }
        var lines: [RecognizedLine] = []
        let tileHeight = 3_072
        let overlap = 256
        var offset = 0
        while offset < image.height {
            try Task.checkCancellation()
            let count = min(tileHeight, image.height - offset)
            guard let tile = image.cropping(to: CGRect(x: 0, y: offset, width: image.width, height: count)) else {
                throw TranslationError.invalidImage
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = mode != .quick
            request.automaticallyDetectsLanguage = language == .automatic
            let supported = try request.supportedRecognitionLanguages()
            request.recognitionLanguages = language.recognitionLanguages.filter { supported.contains($0) }
            request.customWords = recognitionWords
            request.minimumTextHeight = 0.002
            try VNImageRequestHandler(cgImage: tile).perform([request])
            try Task.checkCancellation()
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let box = observation.boundingBox
                let centerFromTop = (1 - box.midY) * Double(count)
                // Each overlapping band has one owner, so repeated real text is preserved
                // while a line recognized in two adjacent tiles is emitted only once.
                if offset > 0 && centerFromTop < Double(overlap / 2) { continue }
                if offset + count < image.height && centerFromTop >= Double(count - overlap / 2) { continue }
                let globalY = (Double(image.height - offset - count) + box.minY * Double(count)) / Double(image.height)
                var line = RecognizedLine(text: candidate.string, x: box.minX, y: globalY,
                    width: box.width, height: box.height * Double(count) / Double(image.height), confidence: candidate.confidence)
                if let range = OCRDateReview.range(in: candidate.string), let observation = try? candidate.boundingBox(for: range) {
                    let date = observation.boundingBox
                    line.dateBox = OCRTextBox(x: date.minX,
                        y: (Double(image.height - offset - count) + date.minY * Double(count)) / Double(image.height),
                        width: date.width, height: date.height * Double(count) / Double(image.height))
                }
                if let range = OCRCurrencyReview.range(in: candidate.string), let observation = try? candidate.boundingBox(for: range) {
                    let amount = observation.boundingBox
                    line.currencyBox = OCRTextBox(x: amount.minX,
                        y: (Double(image.height - offset - count) + amount.minY * Double(count)) / Double(image.height),
                        width: amount.width, height: amount.height * Double(count) / Double(image.height))
                }
                lines.append(line)
            }
            if offset + count == image.height { break }
            offset += tileHeight - overlap
        }
        let rawText = OCRLayout.assemble(lines)
        var attempts = 0, recovered = 0
        let japaneseContext = language == .japanese || (language == .automatic && lines.filter { JapaneseText.kanaCount($0.text) >= 2 }.count >= 2)
        // Quick mode skips general retries but permits one missing numeric
        // field. Professional mode reviews at most eight local regions overall.
        if mode == .professional || mode == .quick {
            var reviewedFieldIndices = Set<Int>()
            for box in OCRFieldReview.regions(in: lines).prefix(mode == .quick ? 1 : 2) {
                try Task.checkCancellation()
                attempts += 1
                do {
                    if let value = try recoverField(box, image: image, language: language, customWords: recognitionWords, japaneseContext: japaneseContext) {
                        reviewedFieldIndices.insert(lines.count)
                        lines.append(value); recovered += 1
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { /* Empty or unrecognisable fields remain empty. */ }
            }
            let candidates = lines.indices.filter { mode == .professional && !reviewedFieldIndices.contains($0)
                && (OCRRefinementPolicy.needsReview(lines[$0], imageHeight: image.height)
                    || OCRCurrencyReview.needsReview(lines[$0], in: lines)
                    || (japaneseContext && OCRScriptReview.needsReview(lines[$0].text))) }
                .sorted {
                    let lc = OCRCurrencyReview.needsReview(lines[$0], in: lines), rc = OCRCurrencyReview.needsReview(lines[$1], in: lines)
                    if lc != rc { return lc }
                    let lhs = japaneseContext && OCRScriptReview.needsReview(lines[$0].text), rhs = japaneseContext && OCRScriptReview.needsReview(lines[$1].text)
                    return lhs != rhs ? lhs : lines[$0].confidence < lines[$1].confidence
                }.prefix(8 - attempts)
            for index in candidates {
                try Task.checkCancellation()
                attempts += 1
                do {
                    if let improved = try refine(lines[index], image: image, language: language, customWords: recognitionWords, japaneseContext: japaneseContext) {
                        lines[index] = improved; recovered += 1
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { /* An optional retry must not discard successful first-pass OCR. */ }
            }
        }
        let selected = cleanScreenText ? OCRLayout.readableLines(lines, aspectRatio: Double(image.height) / Double(image.width)) : lines
        let text = OCRLayout.assemble(selected)
        guard !text.isEmpty else { throw TranslationError.noText }
        return OCRResult(text: text, languages: language == .automatic ? LanguageDetector.describe(text) : language.title,
                         lowConfidence: !OCRFieldReview.regions(in: selected).isEmpty || selected.contains { $0.confidence < 0.55 || OCRDateReview.range(in: $0.text) != nil
                             || OCRCurrencyReview.needsReview($0, in: selected)
                             || (japaneseContext && OCRScriptReview.needsReview($0.text)) }, rawText: rawText,
                         filteredLineCount: lines.count - selected.count, blocks: OCRLayout.readingBlocks(selected),
                         refinementAttempts: attempts, recoveredLineCount: recovered)
    }

    private static func recoverField(_ box: OCRTextBox, image: CGImage, language: SourceLanguage,
                                     customWords: [String], japaneseContext: Bool) throws -> RecognizedLine? {
        let w = Double(image.width), h = Double(image.height)
        let rect = CGRect(x: box.x * w, y: (1 - box.y - box.height) * h,
                          width: box.width * w, height: box.height * h)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard let crop = image.cropping(to: rect), crop.width * 3 <= 2_400 else { return nil }
        // Isolated white-on-dark short values can be missed by Vision's text
        // detector. Invert only that small region, preserving the source pixels.
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            if let probe = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                probe.interpolationQuality = .high
                probe.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
        }
        let luminance = (Double(pixel[0]) * 0.2126 + Double(pixel[1]) * 0.7152 + Double(pixel[2]) * 0.0722) / 255
        let prepared: CGImage
        if luminance < 0.35, let inverted = CIContext(options: [.cacheIntermediates: false]).createCGImage(
            CIImage(cgImage: crop).applyingFilter("CIColorInvert"), from: CGRect(x: 0, y: 0, width: crop.width, height: crop.height)) {
            prepared = inverted
        } else { prepared = crop }
        func read(scale: Int) throws -> (text: String, confidence: Float, bounds: CGRect)? {
            guard let context = CGContext(data: nil, width: prepared.width * scale, height: prepared.height * scale,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(prepared, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
            guard let enlarged = context.makeImage() else { return nil }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = false
            let supported = try request.supportedRecognitionLanguages()
            request.recognitionLanguages = (japaneseContext ? ["ja-JP", "en-US"] : language.recognitionLanguages)
                .filter { supported.contains($0) }
            request.customWords = customWords; request.minimumTextHeight = 0.001
            try VNImageRequestHandler(cgImage: enlarged).perform([request]); try Task.checkCancellation()
            let observations = (request.results ?? []).filter { abs($0.boundingBox.midY - 0.5) < 0.28 }
                .sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            guard !observations.isEmpty else { return nil }
            let candidates = observations.compactMap { $0.topCandidates(1).first }
            let confidence = candidates.map(\.confidence).min() ?? 0
            // Vision assigns 0.5 to some clear, isolated two-character Japanese
            // values. Agreement, numeric syntax and matching pixel positions are
            // required; keep the lower confidence so the app still offers retry.
            guard candidates.count == observations.count, confidence >= 0.5 else { return nil }
            let bounds = observations.reduce(CGRect.null) { $0.union($1.boundingBox) }
            return (candidates.map(\.string).joined(separator: " "), confidence, bounds)
        }
        guard let first = try read(scale: 2), let second = try read(scale: 3),
              let value = OCRFieldReview.agreedValue(first.text, second.text),
              abs(first.bounds.midX - second.bounds.midX) < 0.08,
              abs(first.bounds.midY - second.bounds.midY) < 0.12 else { return nil }
        let bounds = first.bounds
        return RecognizedLine(text: value, x: (rect.minX + bounds.minX * rect.width) / w,
            y: (h - rect.maxY + bounds.minY * rect.height) / h,
            width: bounds.width * rect.width / w, height: bounds.height * rect.height / h,
            confidence: min(first.confidence, second.confidence))
    }

    private static func refine(_ line: RecognizedLine, image: CGImage, language: SourceLanguage,
                               customWords: [String], japaneseContext: Bool) throws -> RecognizedLine? {
        let w = Double(image.width), h = Double(image.height)
        let bounds = CGRect(x: line.x * w, y: (1 - line.y - line.height) * h,
                            width: line.width * w, height: line.height * h)
        let rect = bounds.insetBy(dx: -max(6, bounds.height * 0.25), dy: -max(4, bounds.height * 0.35))
            .intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard let crop = image.cropping(to: rect) else { return nil }
        if let box = line.currencyBox {
            let amountBounds = CGRect(x: box.x * w, y: (1 - box.y - box.height) * h, width: box.width * w, height: box.height * h)
            let amountRect = amountBounds.insetBy(dx: -max(5, amountBounds.height * 0.25), dy: -max(4, amountBounds.height * 0.4))
                .intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
            if let amountCrop = image.cropping(to: amountRect), amountCrop.width * 3 <= 2_400 {
                let prepared = darkTextCrop(amountCrop)
                let first = try readJapanese(prepared, scale: 2), second = try readJapanese(prepared, scale: 3)
                if let first, let second,
                   let value = OCRCurrencyReview.replacement(original: line.text, first: first.text, second: second.text) {
                    var reviewed = line; reviewed.text = value
                    reviewed.confidence = min(first.confidence, second.confidence)
                    return reviewed
                }
            }
        }
        if japaneseContext && OCRScriptReview.needsReview(line.text), crop.width * 3 <= 2_400 {
            let first = try readJapanese(crop, scale: 2), second = try readJapanese(crop, scale: 3)
            if let first, let second,
               let value = OCRScriptReview.replacement(original: line.text, first: first.text, second: second.text) {
                var reviewed = line; reviewed.text = value; reviewed.confidence = min(first.confidence, second.confidence)
                return reviewed
            }
        }
        let dateCrop: CGImage?
        if let box = line.dateBox {
            let dateBounds = CGRect(x: box.x * w, y: (1 - box.y - box.height) * h, width: box.width * w, height: box.height * h)
            let dateRect = dateBounds.insetBy(dx: -max(4, dateBounds.height * 0.15), dy: -max(4, dateBounds.height * 0.35))
                .intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
            dateCrop = image.cropping(to: dateRect)
        } else { dateCrop = nil }
        if OCRDateReview.range(in: line.text) != nil {
            if let dateCrop {
                let first = try readDate(dateCrop, scale: 2), second = try readDate(dateCrop, scale: 3)
                if let first, let second,
                   let text = OCRDateReview.replacement(original: line.text, first: first.text, second: second.text) {
                    var reviewed = line; reviewed.text = text; reviewed.confidence = min(first.confidence, second.confidence)
                    return reviewed
                }
            }
        }
        let scale: Double = min(4.0, max(2.0, 42.0 / max(1.0, Double(bounds.height))), 2400.0 / Double(crop.width))
        guard scale > 1, let context = CGContext(data: nil, width: Int(Double(crop.width) * scale),
            height: Int(Double(crop.height) * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        guard let enlarged = context.makeImage() else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = language == .automatic
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = language.recognitionLanguages.filter { supported.contains($0) }
        request.customWords = Array(customWords.prefix(100)); request.minimumTextHeight = 0.001
        try VNImageRequestHandler(cgImage: enlarged).perform([request])
        try Task.checkCancellation()
        let expected = 1 - (bounds.midY - rect.minY) / rect.height
        let found = (request.results ?? []).filter { abs($0.boundingBox.midY - expected) < 0.25 }
            .sorted { $0.boundingBox.minX < $1.boundingBox.minX }.compactMap { $0.topCandidates(1).first }
        guard !found.isEmpty else { return nil }
        let text = found.map(\.string).joined(separator: " ")
        let confidence = found.map(\.confidence).min() ?? 0
        guard OCRRefinementPolicy.accepts(original: line, replacement: text, confidence: confidence) else { return nil }
        var updated = line; updated.text = text; updated.confidence = confidence
        return updated
    }

    private static func darkTextCrop(_ crop: CGImage) -> CGImage {
        var sample = [UInt8](repeating: 0, count: 4)
        sample.withUnsafeMutableBytes { bytes in
            if let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
        }
        let luminance = (Double(sample[0]) * 0.2126 + Double(sample[1]) * 0.7152 + Double(sample[2]) * 0.0722) / 255
        guard luminance < 0.35 else { return crop }
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(
            CIImage(cgImage: crop).applyingFilter("CIColorInvert"), from: CGRect(x: 0, y: 0, width: crop.width, height: crop.height)) ?? crop
    }

    private static func readDate(_ crop: CGImage, scale: Int) throws -> (text: String, confidence: Float)? {
        // Two pixel scales must fit the budget; repeating an identical capped
        // image would not supply the requested second reading.
        guard crop.width * scale <= 2_400,
              let context = CGContext(data: nil, width: crop.width * scale, height: crop.height * scale,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        guard let image = context.makeImage() else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0.001
        try VNImageRequestHandler(cgImage: image).perform([request]); try Task.checkCancellation()
        let candidates = (request.results ?? []).filter { abs($0.boundingBox.midY - 0.5) < 0.23 }
            .sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            .compactMap { $0.topCandidates(1).first }
        let confidence = candidates.map(\.confidence).min() ?? 0
        guard confidence >= 0.85 else { return nil }
        return (candidates.map(\.string).joined(separator: " "), confidence)
    }

    private static func readJapanese(_ crop: CGImage, scale: Int) throws -> (text: String, confidence: Float)? {
        guard let context = CGContext(data: nil, width: crop.width * scale, height: crop.height * scale,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        guard let image = context.makeImage() else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["ja-JP", "en-US"].filter { supported.contains($0) }
        request.minimumTextHeight = 0.001
        try VNImageRequestHandler(cgImage: image).perform([request]); try Task.checkCancellation()
        let candidates = (request.results ?? []).filter { abs($0.boundingBox.midY - 0.5) < 0.25 }
            .sorted { $0.boundingBox.minX < $1.boundingBox.minX }.compactMap { $0.topCandidates(1).first }
        let confidence = candidates.map(\.confidence).min() ?? 0
        guard confidence >= 0.85 else { return nil }
        return (candidates.map(\.string).joined(separator: " "), confidence)
    }
}

enum LanguageDetector {
    static func describe(_ text: String) -> String {
        var found: [String] = []
        // Use independent recognizers per paragraph; sharing one across tasks is unsafe.
        for paragraph in String(text.prefix(4_000)).components(separatedBy: "\n\n").prefix(12) where paragraph.count >= 2 {
            // Short kana-rich UI labels can be misclassified as unrelated
            // languages by a statistical recognizer. Script is stronger evidence.
            if JapaneseText.kanaCount(paragraph) >= 2 {
                let name = Locale(identifier: "zh-Hans").localizedString(forLanguageCode: "ja") ?? "日语"
                if !found.contains(name) { found.append(name) }
                continue
            }
            // Counts, dates, ID fragments and short brands are not evidence of
            // another language (e.g. AIR SHELL was labelled Indonesian).
            let letters = paragraph.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            guard letters >= 12 else { continue }
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(paragraph)
            if let language = recognizer.dominantLanguage,
               recognizer.languageHypotheses(withMaximum: 1)[language, default: 0] >= 0.7 {
                let name = Locale(identifier: "zh-Hans").localizedString(forLanguageCode: language.rawValue)
                    ?? language.rawValue
                if !found.contains(name) { found.append(name) }
            }
        }
        return found.isEmpty ? "自动识别" : found.prefix(3).joined(separator: " / ")
    }
}
