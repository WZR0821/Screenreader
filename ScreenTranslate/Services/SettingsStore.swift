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
    /// Provider entries that have an API key. Filled by `refreshKeys()`, which
    /// the settings pages call; nothing reads the keychain at launch.
    @Published private(set) var keyedIDs: Set<String> = []
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
        // Keys are stored under the provider entry's id; an empty key removes it.
        for (account, key) in keys { try keychain.write(key, account: account) }
        if !value.saveRecentResult { try clearRecent() }
        else if value.historyLimit != settings.historyLimit {
            let trimmed = Array(try loadHistory().prefix(value.historyLimit))
            try writeHistory(trimmed)
            history = trimmed
        }
        defaults.set(data, forKey: settingsKey)
        settings = value
        if !keys.isEmpty { refreshKeys() }
    }

    func credentials() throws -> (AppSettings, String) {
        let current = settings
        let key = try keychain.read(account: current.activeID)
        guard !key.isEmpty else { throw TranslationError.missingKey }
        return (current, key)
    }

    /// The saved key of one provider entry; empty when there is none.
    func apiKey(for entryID: String) -> String { (try? keychain.read(account: entryID)) ?? "" }

    /// Re-reads which provider entries have a key.
    func refreshKeys() {
        var ids = Set(AIProvider.allCases.map(\.rawValue)).union(settings.configurations.keys)
            .union(settings.providerList ?? [])
        ids.insert(settings.activeID)
        let keyed = ids.filter { !apiKey(for: $0).isEmpty }
        if keyed != keyedIDs { keyedIDs = keyed }
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
        let key = try keychain.read(account: current.activeID)
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

    /// Revisions replace the existing row, without reviving a deleted record.
    @discardableResult
    func replaceRecordedResult(_ expected: TranslationResult, with replacement: TranslationResult) throws -> Bool {
        guard expected.id == replacement.id else { throw TranslationError.reviewConflict }
        guard settings.saveRecentResult else { return false }
        var updated = try loadHistory()
        guard let index = updated.firstIndex(where: { $0.id == expected.id }) else { return false }
        guard updated[index] == expected else { throw TranslationError.reviewConflict }
        updated[index] = replacement
        try writeHistory(updated)
        history = updated
        return true
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

// MARK: - Provider entries

extension SettingsStore {
    /// Entries shown under 供应商.
    var listedProviderIDs: [String] { settings.listedProviderIDs(keyed: keyedIDs) }

    /// Applies one edit to the saved settings.
    func change(keys: [String: String] = [:], _ edit: (inout AppSettings) -> Void) throws {
        var value = settings
        edit(&value)
        try save(value, keys: keys)
    }

    /// Adds a provider with its key. It becomes the one in use only when the
    /// current one has no key yet, so adding never changes a working setup.
    func addProvider(_ kind: AIProvider, configuration: ProviderConfiguration, key: String) throws -> (id: String, activated: Bool) {
        // `save` only checks the address of the entry in use; a new one is checked here.
        _ = try APIClient.endpoint(configuration: configuration)
        refreshKeys()
        var value = settings
        let previous = value.activeID
        let id = value.addProvider(kind, configuration: configuration, keyed: keyedIDs)
        let activated = !keyedIDs.contains(previous)
        if activated {
            value.activate(id)
            // The untouched default provider was never set up; it leaves the list.
            if previous != id, value.configurations[previous] == nil { value.providerList?.removeAll { $0 == previous } }
        }
        try save(value, keys: [id: key])
        return (id, activated)
    }

    /// Removes a provider together with its key.
    func removeProvider(_ entryID: String) throws {
        refreshKeys()
        var value = settings
        guard value.removeProvider(entryID, keyed: keyedIDs) else { return }
        try save(value, keys: [entryID: ""])
    }
}
