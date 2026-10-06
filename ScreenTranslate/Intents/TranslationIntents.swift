import AppIntents
import SwiftUI
import UniformTypeIdentifiers

enum ShortcutTranslationMode: String, AppEnum {
    case saved, ask, quick, professional, visual
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "翻译模式"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .saved: "跟随 App 设置", .ask: "每次询问", .quick: "快速", .professional: "专业", .visual: "识图"
    ]
    var concrete: TranslationMode? {
        switch self { case .quick: return .quick; case .professional: return .professional; case .visual: return .visual; default: return nil }
    }
    static func resolve(_ selection: Self, parameter: IntentParameter<Self>, store: SettingsStore,
                        allowsVisual: Bool = true) async throws -> TranslationMode {
        let settings = await store.settings
        if settings.translationService == .system {
            if let explicit = selection.concrete, explicit != .quick { throw TranslationError.modeUnavailable }
            return .quick
        }
        if selection == .ask || (selection == .saved && settings.askModeInShortcuts) {
            let selected = try await parameter.requestDisambiguation(among: allowsVisual ? [.quick, .professional, .visual] : [.quick, .professional],
                dialog: "请选择翻译模式")
            guard let concrete = selected.concrete else { throw CancellationError() }
            return concrete
        }
        let chosen = selection.concrete ?? settings.mode
        if chosen == .visual && !allowsVisual { throw TranslationError.imageRequired }
        return chosen
    }
}

struct TranslateScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "翻译截图（旧版预览）"
    static let description = IntentDescription("仅用于兼容旧快捷指令，请在读屏设置中安装全文快捷指令。")
    static let isDiscoverable = false
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "图片", supportedContentTypes: [.image])
    var image: IntentFile

    @Parameter(title: "模式", default: .saved) var mode: ShortcutTranslationMode

    static var parameterSummary: some ParameterSummary { Summary("翻译\(\.$image)") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ShowsSnippetView {
        do {
            let store = await SettingsStore.shared
            let chosen = try await ShortcutTranslationMode.resolve(mode, parameter: $mode, store: store)
            let (final, saved) = try await IntentTranslationWork.image(image.data, store: store, mode: chosen)
            return .result(value: final.translated,
                           view: TranslationSnippetView(result: final, error: nil, saved: saved, legacyScreenshot: true))
        } catch is CancellationError { throw CancellationError() }
        catch {
            return .result(value: "", view: TranslationSnippetView(result: nil,
                error: error.localizedDescription, saved: false))
        }
    }
}

struct TranslateTextIntent: AppIntent {
    static let title: LocalizedStringResource = "翻译文字"
    static let description = IntentDescription("使用读屏中保存的 API 设置翻译文字。")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "文字") var text: String
    @Parameter(title: "模式", default: .saved) var mode: ShortcutTranslationMode
    static var parameterSummary: some ParameterSummary { Summary("翻译\(\.$text)") }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ShowsSnippetView {
        do {
            let store = await SettingsStore.shared
            let chosen = try await ShortcutTranslationMode.resolve(mode, parameter: $mode, store: store, allowsVisual: false)
            let (final, saved) = try await IntentTranslationWork.text(text, store: store, mode: chosen)
            return .result(value: final.translated,
                           view: TranslationSnippetView(result: final, error: nil, saved: saved))
        } catch is CancellationError { throw CancellationError() }
        catch {
            return .result(value: "", view: TranslationSnippetView(result: nil,
                error: error.localizedDescription, saved: false))
        }
    }
}

struct TranslateScreenshotDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "翻译截图全文"
    static let description = IntentDescription("将截图翻译为完整文档。在此操作后添加“快速查看”，即可滚动阅读。")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "图片", supportedContentTypes: [.image])
    var image: IntentFile
    @Parameter(title: "模式", default: .saved) var mode: ShortcutTranslationMode
    static var parameterSummary: some ParameterSummary { Summary("翻译\(\.$image)全文") }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let store = await SettingsStore.shared
        let chosen = try await ShortcutTranslationMode.resolve(mode, parameter: $mode, store: store)
        let (result, _) = try await IntentTranslationWork.image(image.data, store: store, mode: chosen)
        let settings = await store.settings
        let data = TranslationDocument.html(result, settings: settings)
        return .result(value: IntentFile(data: data, filename: "Screenreader.html", type: .html))
    }
}

struct ScreenTranslateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TranslateTextIntent(),
            phrases: ["使用\(.applicationName)翻译"], shortTitle: "翻译文字", systemImageName: "character.bubble")
    }
}

enum IntentTranslationWork {
    static func image(_ data: Data, store: SettingsStore,
                      pipeline: TranslationPipeline = TranslationPipeline(), mode: TranslationMode? = nil) async throws -> (TranslationResult, Bool) {
        let savedMode = await store.settings.mode
        let chosen = mode ?? savedMode
        let (settings, key) = try await store.credentials(for: chosen)
        let result = try await pipeline.image(data, settings: settings, key: key)
        return await record(result, store: store)
    }

    static func text(_ text: String, store: SettingsStore,
                     pipeline: TranslationPipeline = TranslationPipeline(), mode: TranslationMode? = nil) async throws -> (TranslationResult, Bool) {
        let savedMode = await store.settings.mode
        let chosen = mode ?? savedMode
        let (settings, key) = try await store.credentials(for: chosen)
        let result = try await pipeline.text(text, settings: settings, key: key)
        return await record(result, store: store)
    }

    @MainActor private static func record(_ result: TranslationResult, store: SettingsStore) -> (TranslationResult, Bool) {
        var result = result
        var saved = store.settings.saveRecentResult
        do { try store.record(result) }
        catch {
            saved = false
            result.warning = [result.warning, "译文已生成，但翻译记录保存失败。"].compactMap { $0 }.joined(separator: "\n")
        }
        return (result, saved)
    }
}
