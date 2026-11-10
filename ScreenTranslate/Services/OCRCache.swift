import Foundation
import CryptoKit

/// Reuses recognition without retaining image bytes. Corrections belong to the
/// current document; only unedited Vision results enter this bounded memory cache.
actor OCRCache {
    static let shared = OCRCache()
    struct Statistics: Equatable { var count: Int; var hits: Int; var bytes: Int }
    private struct Entry { var result: OCRResult; var created: TimeInterval; var access: Int; var bytes: Int }
    private var entries: [String: Entry] = [:]
    private var sequence = 0, generation = 0, hits = 0
    private let capacity: Int
    private let byteLimit: Int
    private let lifetime: TimeInterval

    init(capacity: Int = 8, byteLimit: Int = 2_000_000, lifetime: TimeInterval = 1200) {
        self.capacity = max(0, capacity); self.byteLimit = max(0, byteLimit); self.lifetime = lifetime
    }

    static func key(data: Data, source: SourceLanguage, customWords: [String], cleanScreenText: Bool,
                    mode: TranslationMode, direction: OCRTextDirection) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let options = try encoder.encode(["revision": "OCR-1.2.0", "source": source.rawValue,
            "words": String(decoding: try encoder.encode(customWords), as: UTF8.self),
            "clean": String(cleanScreenText), "mode": mode.rawValue, "direction": direction.rawValue])
        var hash = SHA256(); hash.update(data: data); hash.update(data: options)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func value(for key: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> OCRResult? {
        expire(now)
        guard var entry = entries[key] else { return nil }
        hits += 1; sequence += 1; entry.access = sequence; entries[key] = entry
        var result = entry.result
        result.recognitionSeconds = 0; result.refinementSeconds = 0
        result.refinementAttempts = 0; result.usedCache = true
        return result
    }

    func insert(_ result: OCRResult, for key: String, generation expected: Int,
                now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard expected == generation, capacity > 0, !result.text.isEmpty else { return }
        expire(now)
        var strings = [result.text, result.rawText, result.languages]
        for line in result.lines { strings.append(line.text); strings.append(contentsOf: line.alternatives) }
        for block in result.blocks { strings.append(block.text); strings.append(block.original ?? "") }
        for item in result.reviewItems {
            strings.append(item.text); strings.append(contentsOf: item.reasons); strings.append(contentsOf: item.alternatives)
        }
        let bytes = strings.reduce(0) { $0 + $1.utf8.count * 2 }
            + (result.lines.count + result.blocks.count + result.reviewItems.count) * 256
        guard bytes <= byteLimit else { return }
        sequence += 1
        entries[key] = .init(result: result, created: now, access: sequence, bytes: bytes)
        while entries.count > capacity || entries.values.reduce(0, { $0 + $1.bytes }) > byteLimit {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
            entries.removeValue(forKey: oldest)
        }
    }

    func generationToken() -> Int { generation }
    func clear() { entries.removeAll(); generation += 1; hits = 0 }
    func statistics(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Statistics {
        expire(now)
        return .init(count: entries.count, hits: hits, bytes: entries.values.reduce(0) { $0 + $1.bytes })
    }
    private func expire(_ now: TimeInterval) {
        entries = entries.filter { now >= $0.value.created && now - $0.value.created < lifetime }
    }
}
