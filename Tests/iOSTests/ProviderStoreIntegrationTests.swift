import XCTest
import Security
@testable import ScreenTranslate

/// 1.3.2: provider entries in the settings store, with their keys in the keychain.
@MainActor
final class ProviderStoreIntegrationTests: XCTestCase {
    /// A store on its own defaults suite and keychain service, removed afterwards.
    private func withStore(_ body: (SettingsStore, UserDefaults, KeychainStore) throws -> Void) rethrows {
        let suite = "ScreenTranslate.ProviderStoreTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainStore(service: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: suite] as CFDictionary)
        }
        try body(SettingsStore(defaults: defaults, keychain: keychain), defaults, keychain)
    }

    func testFirstProviderWithAKeyBecomesTheOneInUse() throws {
        try withStore { store, _, _ in
            store.refreshKeys()
            XCTAssertEqual(store.listedProviderIDs, ["deepSeek"], "A new install lists the default provider")
            XCTAssertThrowsError(try store.credentials()) { XCTAssertEqual($0 as? TranslationError, .missingKey) }

            let added = try store.addProvider(.claude, configuration: ProviderConfiguration(provider: .claude), key: "sk-claude")
            XCTAssertEqual(added.id, "claude")
            XCTAssertTrue(added.activated, "Nothing worked before, so the new provider is used at once")
            XCTAssertEqual(store.settings.activeID, "claude")
            XCTAssertEqual(store.listedProviderIDs, ["claude"], "The default that was never set up leaves the list")
            XCTAssertEqual(try store.credentials().1, "sk-claude")
            XCTAssertEqual(store.settings.engineLabel, "Claude · claude-haiku-5-5")
        }
    }

    func testAddingAnotherProviderKeepsTheWorkingOneAndSurvivesRelaunch() throws {
        try withStore { store, defaults, keychain in
            _ = try store.addProvider(.claude, configuration: ProviderConfiguration(provider: .claude), key: "sk-claude")
            let second = try store.addProvider(.deepSeek, configuration: ProviderConfiguration(provider: .deepSeek), key: "sk-deepseek")
            XCTAssertFalse(second.activated, "Adding must not change a working setup")
            XCTAssertEqual(store.settings.activeID, "claude")
            XCTAssertEqual(store.listedProviderIDs, ["claude", "deepSeek"])
            XCTAssertEqual(store.keyedIDs, ["claude", "deepSeek"])

            try store.change { $0.activate("deepSeek", model: "deepseek-v4-pro") }
            let reloaded = SettingsStore(defaults: defaults, keychain: keychain)
            reloaded.refreshKeys()
            XCTAssertEqual(reloaded.settings.activeID, "deepSeek")
            XCTAssertEqual(reloaded.settings.configurations, store.settings.configurations)
            XCTAssertEqual(reloaded.listedProviderIDs, ["claude", "deepSeek"])
            XCTAssertEqual(reloaded.settings.configuration.model, "deepseek-v4-pro")
            XCTAssertEqual(try reloaded.credentials().1, "sk-deepseek")
            XCTAssertEqual(reloaded.apiKey(for: "claude"), "sk-claude")
        }
    }

    func testCustomServicesGetSeparateEntriesAndKeys() throws {
        try withStore { store, _, _ in
            var one = ProviderConfiguration(provider: .custom)
            one.baseURL = "https://one.test/v1"; one.model = "model-one"; one.name = "One"
            var two = one
            two.baseURL = "https://two.test/v1"; two.model = "model-two"; two.name = "Two"
            let first = try store.addProvider(.custom, configuration: one, key: "key-one")
            let second = try store.addProvider(.custom, configuration: two, key: "key-two")
            XCTAssertEqual(first.id, "custom", "The first custom service keeps the id earlier versions used")
            XCTAssertTrue(second.id.hasPrefix("custom-"))
            XCTAssertTrue(first.activated); XCTAssertFalse(second.activated)
            XCTAssertEqual(store.apiKey(for: first.id), "key-one")
            XCTAssertEqual(store.apiKey(for: second.id), "key-two")
            XCTAssertEqual(store.settings.displayName(for: second.id), "Two")

            try store.change { $0.activate(second.id) }
            XCTAssertEqual(store.settings.provider, .custom)
            XCTAssertEqual(try store.credentials().1, "key-two")
            XCTAssertEqual(store.settings.configuration.baseURL, "https://two.test/v1")
            XCTAssertEqual(store.settings.engineLabel, "Two · model-two")
        }
    }

    func testRemovingAProviderDeletesItsKeyAndSettingsButNeverTheOneInUse() throws {
        try withStore { store, _, _ in
            _ = try store.addProvider(.claude, configuration: ProviderConfiguration(provider: .claude), key: "sk-claude")
            _ = try store.addProvider(.kimi, configuration: ProviderConfiguration(provider: .kimi), key: "sk-kimi")
            try store.removeProvider("kimi")
            XCTAssertEqual(store.listedProviderIDs, ["claude"])
            XCTAssertEqual(store.apiKey(for: "kimi"), "")
            XCTAssertNil(store.settings.configurations["kimi"])
            XCTAssertEqual(store.keyedIDs, ["claude"])

            try store.removeProvider("claude")
            XCTAssertEqual(store.settings.activeID, "claude")
            XCTAssertEqual(store.listedProviderIDs, ["claude"])
            XCTAssertEqual(try store.credentials().1, "sk-claude")
        }
    }

    func testAnInvalidAddressIsRejectedBeforeAnythingIsStored() throws {
        try withStore { store, _, _ in
            var broken = ProviderConfiguration(provider: .custom)
            broken.baseURL = "http://insecure.test/v1"; broken.model = "m"
            XCTAssertThrowsError(try store.addProvider(.custom, configuration: broken, key: "key")) {
                XCTAssertEqual($0 as? TranslationError, .invalidURL)
            }
            XCTAssertEqual(store.apiKey(for: "custom"), "", "No key is written when the settings cannot be saved")
            XCTAssertEqual(store.settings.activeID, "deepSeek")
            XCTAssertNil(store.settings.configurations["custom"])
        }
    }

    func testSettingsSavedByEarlierVersionsShowTheProvidersThatHaveKeys() throws {
        try withStore { _, defaults, keychain in
            // What 1.3.1 stores: the provider in use, per-provider settings, and
            // one keychain item per provider that was given a key.
            let saved = #"{"provider":"openAI","configurations":{"openAI":{"baseURL":"https://api.openai.com/v1","model":"gpt-6.1-sol","style":"responses"},"custom":{"baseURL":"https://mock.test/v1","model":"saved-model","style":"chatCompletions"}}}"#
            defaults.set(Data(saved.utf8), forKey: "screenTranslate.settings.v1")
            try keychain.write("sk-openai", provider: .openAI)
            try keychain.write("sk-custom", provider: .custom)

            let store = SettingsStore(defaults: defaults, keychain: keychain)
            store.refreshKeys()
            XCTAssertEqual(store.settings.activeID, "openAI")
            XCTAssertEqual(store.listedProviderIDs, ["openAI", "custom"])
            XCTAssertEqual(store.settings.configuration.model, "gpt-6.1-sol")
            XCTAssertEqual(try store.credentials().1, "sk-openai")
            XCTAssertEqual(store.settings.savedModels(for: "custom").map(\.id), ["saved-model"])
            XCTAssertEqual(store.settings.savedModels(for: "openAI").map(\.id), ["gpt-6-luna", "gpt-6.1-sol", "gpt-4.1-mini"])
        }
    }
}
