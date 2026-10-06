import Foundation
import CryptoKit

/// Bounded, process-local cache. No screenshots, credentials or cache files are stored.
actor TranslationCache {
    static let shared = TranslationCache()
    private struct Entry { var output: TranslationOutput; var created: TimeInterval; var access: Int; var bytes: Int }
    private var entries: [String: Entry] = [:]
    private var sequence = 0
    private let capacity: Int
    private let byteLimit: Int
    private let lifetime: TimeInterval

    init(capacity: Int = 40, byteLimit: Int = 1_000_000, lifetime: TimeInterval = 1200) {
        self.capacity = max(0, capacity); self.byteLimit = max(0, byteLimit); self.lifetime = lifetime
    }

    static func key(text: String, settings: AppSettings, apiKey: String,
                    readingBlocks: [ReadingBlock]?, fromImageText: Bool, engine: String = "api") throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let config = String(decoding: try encoder.encode(settings.configuration), as: UTF8.self)
        let blocks = String(decoding: try encoder.encode(readingBlocks), as: UTF8.self)
        let identity = ["version": TranslationPrompts.revision, "engine": engine, "text": text, "blocks": blocks,
            "provider": settings.provider.rawValue, "configuration": config, "source": settings.source.rawValue,
            "target": settings.target.rawValue, "mode": settings.mode.rawValue, "tone": settings.tone.rawValue,
            "prompt": settings.customPrompt, "glossary": settings.glossary, "fromImage": String(fromImageText),
            "credential": digest(Data(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).utf8))]
        return digest(try encoder.encode(identity))
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func value(for key: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TranslationOutput? {
        expire(now: now)
        guard var entry = entries[key] else { return nil }
        sequence += 1; entry.access = sequence; entries[key] = entry
        return entry.output
    }

    func insert(_ output: TranslationOutput, for key: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        expire(now: now)
        guard !output.text.isEmpty, let data = try? JSONEncoder().encode(output.blocks), capacity > 0 else { return }
        let size = output.text.utf8.count + data.count + (output.warning?.utf8.count ?? 0)
        guard size <= byteLimit else { return }
        sequence += 1
        entries[key] = Entry(output: output, created: now, access: sequence, bytes: size)
        while entries.count > capacity || entries.values.reduce(0, { $0 + $1.bytes }) > byteLimit {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { break }
            entries.removeValue(forKey: oldest)
        }
    }

    func clear() { entries.removeAll() }
    private func expire(now: TimeInterval) { entries = entries.filter { now >= $0.value.created && now - $0.value.created < lifetime } }
}
