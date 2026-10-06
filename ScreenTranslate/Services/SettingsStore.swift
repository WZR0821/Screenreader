import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    static let shared: SettingsStore = {
        #if DEBUG
        if DebugFixtures.enabled { return DebugFixtures.makeStore() }
        #endif
        return SettingsStore()
    }()
    @Published private(set) var settings: AppSettings
    @Published private(set) var history: [TranslationResult] = []
    var recentResult: TranslationResult? { history.first }
    let keychain: KeychainStore
    private let defaults: UserDefaults
    private let directory: URL
    private let settingsKey = "screenTranslate.settings.v1"
    private var recentURL: URL { directory.appendingPathComponent("recent-result.json") }
    private var historyURL: URL { directory.appendingPathComponent("history.json") }

    init(defaults: UserDefaults = .standard, directory: URL? = nil,
         keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                    in: .userDomainMask)[0].appendingPathComponent("ScreenTranslate", isDirectory: true)
        if let data = defaults.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(AppSettings.self, from: data) { settings = saved }
        else { settings = AppSettings() }
        refreshRecent()
    }

    func save(_ value: AppSettings, keys: [String: String]) throws {
        var value = value
        value.normalizePreferences()
        guard value.glossary.count <= 4_000 else { throw TranslationError.tooMuchGlossary }
        guard value.modePrompts.values.allSatisfy({ $0.count <= TextPreparation.maximumPromptCharacters }) else { throw TranslationError.tooMuchPrompt }
        // Incomplete setup can be saved; translation validates the fields before any upload.
        if !value.configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = try APIClient.endpoint(configuration: value.configuration)
        }
        let data = try JSONEncoder().encode(value)
        for provider in AIProvider.allCases {
            if let key = keys[provider.rawValue] { try keychain.write(key, provider: provider) }
        }
        if !value.saveRecentResult { try clearRecent() }
        else if value.historyLimit != settings.historyLimit {
            let trimmed = Array(try loadHistory().prefix(value.historyLimit))
            try writeHistory(trimmed)
            history = trimmed
        }
        defaults.set(data, forKey: settingsKey)
        settings = value
    }

    func credentials() throws -> (AppSettings, String) {
        let current = settings
        let key = try keychain.read(provider: current.provider)
        guard !key.isEmpty else { throw TranslationError.missingKey }
        return (current, key)
    }

    func updateLanguages(source: SourceLanguage, target: TargetLanguage) throws {
        var updated = settings
        updated.source = source
        updated.target = target
        try save(updated, keys: [:])
    }

    func swapLanguages() throws {
        guard settings.source != .automatic else { return }
        var updated = settings
        updated.swapLanguages()
        try save(updated, keys: [:])
    }

    func updateImageMode(_ mode: ImageTranslationMode) throws {
        var updated = settings
        updated.imageMode = mode
        try updateMode(updated.mode)
    }

    func updateMode(_ mode: TranslationMode) throws {
        guard settings.allowedModes.contains(mode) else { throw TranslationError.modeUnavailable }
        var updated = settings
        updated.mode = mode
        try save(updated, keys: [:])
    }

    func updateQuickEngine(_ engine: QuickTranslationEngine) throws {
        var updated = settings
        updated.quickEngine = engine
        try save(updated, keys: [:])
    }

    func credentials(for mode: TranslationMode) throws -> (AppSettings, String) {
        guard settings.allowedModes.contains(mode) else { throw TranslationError.modeUnavailable }
        var current = settings
        current.mode = mode
        let key = try keychain.read(provider: current.provider)
        guard !key.isEmpty else { throw TranslationError.missingKey }
        return (current, key)
    }

    func record(_ result: TranslationResult) throws {
        guard settings.saveRecentResult else { return }
        var updated = try loadHistory()
        updated.removeAll { $0.id == result.id }
        updated.insert(result, at: 0)
        updated = Array(updated.prefix(settings.historyLimit))
        try writeHistory(updated)
        history = updated
    }

    func deleteResult(_ id: UUID) throws {
        let updated = try loadHistory().filter { $0.id != id }
        try writeHistory(updated)
        history = updated
    }

    private func loadHistory() throws -> [TranslationResult] {
        do {
            if FileManager.default.fileExists(atPath: historyURL.path) {
                return try JSONDecoder().decode([TranslationResult].self, from: Data(contentsOf: historyURL))
            }
            if FileManager.default.fileExists(atPath: recentURL.path) {
                return [try JSONDecoder().decode(TranslationResult.self, from: Data(contentsOf: recentURL))]
            }
            return []
        } catch { throw TranslationError.persistence }
    }

    private func writeHistory(_ results: [TranslationResult]) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(results).write(to: historyURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            // Once the new file is safely written, the legacy file is no longer authoritative.
            if FileManager.default.fileExists(atPath: recentURL.path) { try FileManager.default.removeItem(at: recentURL) }
        } catch { throw TranslationError.persistence }
    }

    func clearRecent() throws {
        do {
            for url in [recentURL, historyURL] where FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            history = []
        } catch { throw TranslationError.persistence }
    }

    func refreshRecent() {
        guard settings.saveRecentResult else { history = []; return }
        guard let saved = try? loadHistory() else { return }
        history = Array(saved.prefix(settings.historyLimit))
        if !saved.isEmpty && !FileManager.default.fileExists(atPath: historyURL.path) {
            try? writeHistory(history)
        }
    }
}
