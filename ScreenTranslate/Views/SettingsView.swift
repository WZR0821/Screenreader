import SwiftUI

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject var store: SettingsStore
    @State private var draft = AppSettings()
    @State private var keys: [String: String] = [:]
    @State private var revealKey = false
    @State private var notice: String?
    @State private var error: String?
    @State private var models: [String] = []
    @State private var showModels = false
    @State private var busy = false
    @State private var loaded = false
    @State private var advanced = false
    @State private var confirmClear = false
    @State private var job: Task<Void, Never>?
    @FocusState private var editing: Bool

    private var config: Binding<ProviderConfiguration> {
        Binding(get: { draft.configuration }, set: { draft.configuration = $0 })
    }
    private var key: Binding<String> {
        Binding(get: { keys[draft.provider.rawValue] ?? "" },
                set: { keys[draft.provider.rawValue] = $0 })
    }
    private var client: APIClient { TranslationPipeline().client }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if typeSize >= .xxLarge || geometry.size.height < 520 {
                    ScrollView { overview(compact: true) }
                        .accessibilityIdentifier("settingsAccessibleScroll")
                } else {
                    overview(compact: false)
                }
            }
            .background(Theme.background)
            .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func overview(compact: Bool) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image("BrandMark").resizable().frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("读屏").font(.title3.weight(.semibold))
                    Text("截图与文字翻译").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.top, 6)
            VStack(spacing: 0) {
                overviewLink("翻译", detail: "\(store.settings.source.title) → \(store.settings.target.title)", icon: "character.bubble", id: "basicSettingsLink", compact: compact) { basicSettings }
                menuDivider
                overviewLink("API 设置", detail: store.settings.provider.title + " · " + (store.settings.configuration.model.isEmpty ? "选择模型" : store.settings.configuration.model), icon: "network", id: "apiSettingsLink", compact: compact) { apiSettings }
                menuDivider
                overviewLink("模式提示词", detail: "快速、专业、识图分别设置", icon: "text.bubble", id: "promptSettingsLink", compact: compact) { PromptSettingsView(store: store) }
                menuDivider
                overviewLink("外观与阅读", detail: "颜色、字号与阅读间距", icon: "circle.lefthalf.filled", id: "displaySettingsLink", compact: compact) { displaySettings }
                menuDivider
                overviewLink("缓存与记录", detail: "保留 \(store.settings.historyLimit) 条 · 翻译缓存", icon: "clock", id: "dataSettingsLink", compact: compact) { dataSettings }
                menuDivider
                overviewLink("操作按钮", detail: "截屏 → 翻译 → 全文弹窗", icon: "button.programmable", id: "fullScreenShortcutLink", compact: compact) { ShortcutGuideContent() }
                menuDivider
                overviewLink("使用说明", detail: "开始使用读屏", icon: "questionmark.circle", id: "usageGuideLink", compact: compact) { UsageGuideView() }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            VStack(spacing: 4) {
                Text("WANG ZIRUI").font(.caption.weight(.medium)).accessibilityIdentifier("developerCredit")
                Text("读屏 · Screenreader  \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                    .font(.caption2).accessibilityIdentifier("appVersionLabel")
            }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 6)
        }.padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var menuDivider: some View { Divider().padding(.leading, 52) }
    private func overviewLink<Destination: View>(_ title: String, detail: String, icon: String,
        id: String, compact: Bool, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(compact ? 2 : 1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 16).padding(.vertical, compact ? 14 : 6)
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: compact ? nil : .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private var displaySettings: some View {
        Form {
            NavigationLink { AppearanceSettingsView(store: store) } label: {
                settingsRow("外观与颜色", detail: "\(store.settings.appearance.title) · \(store.settings.accentTheme.title)", icon: "circle.lefthalf.filled")
            }.accessibilityIdentifier("appearanceSettingsLink")
            NavigationLink { ReaderSettingsView(store: store) } label: {
                settingsRow("译文显示", detail: "字号、间距与原文显示", icon: "textformat.size")
            }.accessibilityIdentifier("readerSettingsLink")
        }.scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("外观与阅读").navigationBarTitleDisplayMode(.inline)
    }

    private var dataSettings: some View {
        Form {
            Section {
                Toggle("复用近期译文", isOn: $draft.cacheTranslations).accessibilityIdentifier("translationCacheToggle")
                Button("清除临时缓存") {
                    Task { await TranslationCache.shared.clear(); notice = "临时缓存已清除。" }
                }.accessibilityIdentifier("clearTranslationCache")
            } header: { Text("翻译速度") } footer: {
                Text("相同文字、语言、模型及模式要求可在 20 分钟内复用译文。缓存仅存于内存，不缓存图片。")
            }
            Section {
                Toggle("保存翻译记录", isOn: $draft.saveRecentResult).accessibilityIdentifier("saveRecentToggle")
                Picker("保留条数", selection: $draft.historyLimit) {
                    ForEach([10, 30, 100], id: \.self) { Text("\($0) 条").tag($0) }
                }.disabled(!draft.saveRecentResult).accessibilityIdentifier("historyLimitPicker")
                Button("清空翻译记录", role: .destructive) { confirmClear = true }.disabled(store.history.isEmpty)
            } header: { Text("翻译记录 · 已保存 \(store.history.count) 条") } footer: {
                Text("文字仅保存在本机，不保存截图。达到上限时移除最早的记录。关闭记录并保存后，已有记录也会清空。")
            }
        }.scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("缓存与记录").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { feedback }
            .confirmationDialog("清空全部翻译记录？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空记录", role: .destructive) {
                    do { try store.clearRecent(); notice = "记录已清空。"; error = nil }
                    catch { self.error = error.localizedDescription }
                }
            } message: { Text("清空后无法恢复。") }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        var value = store.settings
                        value.cacheTranslations = draft.cacheTranslations
                        value.saveRecentResult = draft.saveRecentResult
                        value.historyLimit = draft.historyLimit
                        save(value, keys: [:])
                    }.fontWeight(.semibold).accessibilityIdentifier("saveSettingsButton")
                }
            }.onAppear { draft = store.settings; notice = nil; error = nil }
    }

    private var basicSettings: some View {
        Form {
            Section {
                Picker("翻译服务", selection: Binding(get: { store.settings.translationService }, set: { service in
                    do { try store.updateQuickEngine(service); draft = store.settings; error = nil }
                    catch { self.error = error.localizedDescription }
                })) {
                    ForEach(TranslationService.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("translationServicePicker")
            } footer: {
                Text("系统翻译仅用于 App 内快速模式。操作按钮使用 API；专业和识图模式也需要 API。")
            }

            Section {
                Picker("原文语言", selection: $draft.source) {
                    ForEach(SourceLanguage.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("settingsSourceLanguagePicker")
                Picker("目标语言", selection: $draft.target) {
                    ForEach(TargetLanguage.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("settingsTargetLanguagePicker")
                Picker("表达风格", selection: $draft.tone) {
                    ForEach(TranslationTone.allCases) { Text($0.title).tag($0) }
                }.disabled(store.settings.translationService == .system)
            } header: { Text("语言与表达") } footer: {
                Text("支持中文、英语和日语。自动识别可处理混合语言，原文语言也用于辅助识字。修改后请保存。")
            }
            Section {
                Picker("默认模式", selection: $draft.mode) {
                    ForEach(store.settings.allowedModes) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("defaultModePicker")
                Toggle("每次运行时选择模式", isOn: $draft.askModeInShortcuts)
                    .accessibilityIdentifier("askModeInShortcutsToggle").disabled(store.settings.translationService == .system)
                Toggle("过滤屏幕控件", isOn: $draft.cleanScreenText)
                    .accessibilityIdentifier("cleanScreenTextToggle")
            } header: { Text("模式与操作按钮") } footer: {
                Text("快速模式完整简译；专业模式保留段落、列表及价格关系；识图模式解释文字与画面。也可在翻译页切换。")
            }
            if store.settings.translationService == .api {
            Section("术语表") {
                TextField("例如：checkout → payment", text: $draft.glossary, axis: .vertical)
                    .lineLimit(3...7).focused($editing).accessibilityIdentifier("glossaryField")
                Text("\(draft.glossary.count) / 4000 字符").font(.caption).foregroundStyle(.secondary)
            }
            }


        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("翻译").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { feedback }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { saveBasics() }.fontWeight(.semibold)
                    .accessibilityIdentifier("saveSettingsButton")
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { editing = false } }
        }
        .onAppear { draft = store.settings; notice = nil; error = nil }
    }

    private var apiSettings: some View {
        Form {
            Section {
                Picker("服务商", selection: $draft.provider) {
                    ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("providerPicker")
                Button { showModels = true } label: {
                    HStack {
                        Text("模型").foregroundStyle(.primary)
                        Spacer()
                        Text(draft.configuration.model.isEmpty ? "选择模型" : draft.configuration.model)
                            .lineLimit(1).foregroundStyle(theme.accent)
                        Image(systemName: "chevron.right").font(.caption)
                    }.frame(minHeight: 32)
                }.accessibilityIdentifier("chooseModelButton")
                if draft.provider == .custom {
                    TextField("模型 ID", text: config.model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                        .accessibilityIdentifier("modelField")
                }
            } header: { Text("服务商与模型") } footer: {
                Text(draft.provider == .custom ? "填写 API 地址和模型 ID，支持 OpenAI 兼容格式及 Claude 接口。" : draft.provider.setupNote)
            }.disabled(busy)
            Section {
                HStack {
                    Group {
                        if revealKey { TextField("API Key", text: key) }
                        else { SecureField("API Key", text: key) }
                    }.textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                        .accessibilityIdentifier("apiKeyField")
                    Button { revealKey.toggle() } label: {
                        Image(systemName: revealKey ? "eye.slash" : "eye").frame(width: 44, height: 44)
                    }.buttonStyle(.borderless).accessibilityLabel(revealKey ? "隐藏密钥" : "显示密钥")
                }
                Button("获取可用模型") { fetchModels() }.accessibilityIdentifier("fetchModelsButton")
            } header: { Text("API 密钥") } footer: {
                Text("密钥仅保存在本机钥匙串中。可用模型取决于服务商账户权限。")
            }.disabled(busy)
            Section {
                Button { testConnection() } label: {
                    Label("测试连接", systemImage: "checkmark.circle").frame(minHeight: 32)
                }.accessibilityIdentifier("testConnectionButton")
            } footer: { Text("测试会发送“Hello.”，可能产生少量 API 费用。连接成功后请保存。") }.disabled(busy)
            Section {
                DisclosureGroup("高级设置", isExpanded: $advanced) {
                    TextField("https://…", text: config.baseURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($editing).accessibilityLabel("API 地址").accessibilityIdentifier("apiURLField")
                    Picker("接口格式", selection: config.style) {
                        ForEach(APIStyle.allCases) { Text($0.title).tag($0) }
                    }
                    if draft.provider != .custom {
                        TextField("自定义模型 ID", text: config.model)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                            .accessibilityIdentifier("modelField")
                    }
                }
                Link("官方 API 文档", destination: draft.provider.documentationURL)
            }.disabled(busy)
            Section {
                Label("图片上传说明", systemImage: "checkmark.shield").font(.subheadline)
                Text("快速和专业模式只发送文字；识图模式发送压缩图片，记录中不保存图片。每个服务商分别保存地址、模型和密钥。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("API").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { feedback }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { saveAPI() }.fontWeight(.semibold).disabled(busy)
                    .accessibilityIdentifier("saveSettingsButton")
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { editing = false } }
        }
        .onAppear { draft = store.settings; loadKeys(); notice = nil; advanced = draft.provider == .custom }
        .onChange(of: draft.provider) { _, provider in
            models = []; notice = nil; error = nil; advanced = provider == .custom
            if draft.configuration.model.isEmpty { draft.configuration.model = provider.models.first?.id ?? "" }
        }
        .onDisappear { job?.cancel(); revealKey = false }
        .sheet(isPresented: $showModels) {
            ModelSelectionView(provider: draft.provider, fetched: models, selection: config.model)
        }
    }

    private func settingsRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 5)
    }

    private var feedback: some View {
        VStack(spacing: 8) {
            if busy {
                HStack { ProgressView(); Text("正在连接…"); Spacer(); Button("取消") { job?.cancel() } }
                    .font(.subheadline).padding(12)
            }
            if let error { ErrorBanner(message: error) }
            if let notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .accessibilityIdentifier("settingsNotice")
            }
        }.padding(.horizontal, 16).background(Theme.background)
    }

    private func loadKeys() {
        guard !loaded else { return }
        for provider in AIProvider.allCases {
            do { keys[provider.rawValue] = try store.keychain.read(provider: provider) }
            catch { self.error = error.localizedDescription }
        }
        loaded = true
    }

    private func saveBasics() {
        var value = store.settings
        value.source = draft.source; value.target = draft.target
        value.tone = draft.tone; value.glossary = draft.glossary
        value.cleanScreenText = draft.cleanScreenText; value.mode = draft.mode
        value.askModeInShortcuts = draft.askModeInShortcuts
        save(value, keys: [:])
    }

    private func saveAPI() {
        var value = store.settings
        value.provider = draft.provider; value.configurations = draft.configurations
        save(value, keys: keys)
    }

    private func save(_ value: AppSettings, keys: [String: String]) {
        editing = false
        do {
            try store.save(value, keys: keys)
            if !value.cacheTranslations { Task { await TranslationCache.shared.clear() } }
            error = nil
            notice = "设置已保存，操作按钮使用同一配置。"
        } catch { self.error = error.localizedDescription; notice = nil }
    }

    private func fetchModels() {
        editing = false; busy = true; error = nil; notice = nil
        let configuration = draft.configuration
        let apiKey = key.wrappedValue
        job = Task {
            defer { busy = false }
            do {
                models = try await client.models(configuration: configuration, apiKey: apiKey)
                try Task.checkCancellation()
                showModels = true
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }

    private func testConnection() {
        editing = false; busy = true; error = nil; notice = nil
        var snapshot = store.settings
        snapshot.provider = draft.provider; snapshot.configurations = draft.configurations
        snapshot.mode = .quick; snapshot.source = .english; snapshot.target = .simplifiedChinese; snapshot.glossary = ""; snapshot.customPrompt = ""
        let apiKey = key.wrappedValue
        job = Task {
            defer { busy = false }
            do {
                _ = try await client.translate("Hello.", settings: snapshot, apiKey: apiKey, timeout: 15)
                try Task.checkCancellation()
                notice = "连接成功，请保存后开始翻译。"
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
