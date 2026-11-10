import SwiftUI
@preconcurrency import Translation

struct LanguagePacksView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var source: TargetLanguage = .japanese
    @State private var target: TargetLanguage = .simplifiedChinese
    @State private var status: LanguageAvailability.Status?
    @State private var checking = false
    @State private var preparing = false
    @State private var notice: String?
    @State private var failure: String?
    @State private var configuration: TranslationSession.Configuration?
    private var pair: String { source.rawValue + target.rawValue }

    init(source: SourceLanguage = .automatic, target: TargetLanguage = .simplifiedChinese) {
        _source = State(initialValue: source.targetLanguage ?? (target == .japanese ? .english : .japanese))
        _target = State(initialValue: target)
    }

    var body: some View {
        Form {
            Section("本机语言包") {
                Picker("原文语言", selection: $source) {
                    ForEach(TargetLanguage.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("languagePackSourcePicker")
                Picker("目标语言", selection: $target) {
                    ForEach(TargetLanguage.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("languagePackTargetPicker")
                LabeledContent("状态", value: statusText).accessibilityIdentifier("languagePackStatus")
                if checking || preparing { ProgressView(preparing ? "正在准备语言包…" : "正在检查…") }
                if status == .supported && source != target {
                    Button("下载语言包") {
                        failure = nil; notice = nil; preparing = true
                        configuration = .init(source: .init(identifier: source.languageCode), target: .init(identifier: target.languageCode))
                    }.accessibilityIdentifier("downloadLanguagePacks")
                }
                Button("刷新状态") { Task { await refresh() } }.disabled(checking)
            }.disabled(preparing)
            Section {
                Text("语言包安装后可在本机离线快速翻译。下载由 iOS 提供，需要按系统提示确认。此页面不会发送文字或图片到 AI 服务。")
                Text("自动识别会在翻译时检查对应语言；可在这里提前准备常用的语言组合。操作按钮仍使用 API。")
                if let notice { Label(notice, systemImage: "checkmark.circle").foregroundStyle(.green) }
                if let failure { ErrorBanner(message: failure) }
            }.font(.footnote)
        }.navigationTitle("本机语言包").navigationBarTitleDisplayMode(.inline)
            .task(id: pair) { notice = nil; failure = nil; await refresh() }
            .onChange(of: scenePhase) { _, value in if value == .active { Task { await refresh() } } }
            .translationTask(configuration) { session in
                do {
                    try await session.prepareTranslation()
                    try Task.checkCancellation()
                    notice = "语言包已准备好。"
                } catch { failure = "语言包未准备完成：\(error.localizedDescription)。可稍后重试。" }
                preparing = false; configuration = nil
                await refresh()
            }
    }

    private var statusText: String {
        #if targetEnvironment(simulator)
        return "请在 iPhone 真机检查"
        #else
        if source == target { return "相同语言，无需翻译" }
        switch status {
        case .installed: return "已安装 · 可离线使用"
        case .supported: return "尚需下载"
        case .unsupported: return "暂不支持此语言组合"
        default: return "检查中"
        }
        #endif
    }

    @MainActor private func refresh() async {
        #if !targetEnvironment(simulator)
        guard source != target else { status = nil; checking = false; return }
        let requestedPair = pair
        checking = true; status = nil
        let value = await LanguageAvailability().status(from: .init(identifier: source.languageCode), to: .init(identifier: target.languageCode))
        guard !Task.isCancelled, requestedPair == pair else { return }
        status = value; checking = false
        #endif
    }
}
