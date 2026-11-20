import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    // Every page here applies a change as soon as it is made.
    @State private var glossary = ""
    @State private var notice: String?
    @State private var error: String?
    @State private var historyChange: HistoryChange?
    @State private var cacheStats = TranslationCache.Statistics(count: 0, bytes: 0, hits: 0, misses: 0)
    @State private var ocrCacheStats = OCRCache.Statistics(count: 0, hits: 0, bytes: 0)
    @FocusState private var editing: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Changes that delete saved records ask first.
    private enum HistoryChange: Equatable {
        case clearAll, disable, limit(Int)
    }

    /// The home page fills one screen exactly: its rows share whatever height a
    /// taller phone leaves over, so nothing scrolls and no gap is left above the
    /// tab bar. A system list cannot do that, so the groups are drawn here to
    /// look like one. Large text or a short screen still scrolls.
    var body: some View {
        NavigationStack {
            OneScreenPage(identifier: "settingsAccessibleScroll") { size in
                // The margin the system gives a grouped list at this width.
                let margin: CGFloat = size.width >= 400 ? 20 : 16
                FillStack {
                    brand
                    Group {
                        groupTitle("翻译与阅读")
                        overviewLink("翻译偏好", value: "\(store.settings.source.title) → \(store.settings.target.title)", icon: "character.bubble.fill", color: .blue, id: "basicSettingsLink", position: .first, edge: margin) { basicSettings }
                        overviewLink("外观与阅读", icon: "textformat.size", color: .indigo, id: "displaySettingsLink", position: .last, edge: margin) { displaySettings }
                    }
                    Group {
                        groupTitle("AI 配置")
                        overviewLink("AI 大模型", value: store.settings.displayName(for: store.settings.activeID), icon: "sparkles", color: .green, id: "apiSettingsLink", position: .first, edge: margin) { AIModelsView(store: store) }
                        overviewLink("模式提示词", value: store.settings.modePrompts.isEmpty ? "默认" : "已自定义", icon: "text.bubble.fill", color: .purple, id: "promptSettingsLink", position: .last, edge: margin) { PromptSettingsView(store: store) }
                    }
                    Group {
                        groupTitle("数据与帮助")
                        overviewLink("缓存与记录", value: store.settings.saveRecentResult ? "\(store.history.count) 条" : "已关闭", icon: "clock.fill", color: .orange, id: "dataSettingsLink", position: .first, edge: margin) { dataSettings }
                        overviewLink("操作按钮", icon: "button.programmable", color: .gray, id: "fullScreenShortcutLink", position: .middle, edge: margin) { ShortcutGuideContent() }
                        overviewLink("使用说明", icon: "questionmark", color: .blue, id: "usageGuideLink", position: .last, edge: margin) { UsageGuideView() }
                    }
                    credit
                }
                .padding(.horizontal, margin)
            }
            .background(Theme.background)
            .navigationTitle("设置").navigationBarTitleDisplayMode(.large)
        }
    }

    private var brand: some View {
        HStack(spacing: 14) {
            Image("BrandMark").resizable().frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12.5, style: .continuous)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("读屏").font(.title2.weight(.semibold))
                Text("截图与文字翻译").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title).font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 21).padding(.bottom, 5)
            .accessibilityAddTraits(.isHeader)
    }

    private var credit: some View {
        VStack(spacing: 5) {
            Text("Jerry Wong").font(.footnote.weight(.medium)).accessibilityIdentifier("developerCredit")
            Text("读屏 · Screenreader  \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                .font(.caption).accessibilityIdentifier("appVersionLabel")
        }
        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 8)
    }

    /// A row in the style of the system Settings app: colored icon, title, and
    /// the current value on the trailing side.
    /// - Parameter edge: the space after the chevron, which follows the page margin as in a system list.
    private func overviewLink<Destination: View>(_ title: String, value: String? = nil, icon: String, color: Color,
        id: String, position: GroupPosition, edge: CGFloat, @ViewBuilder destination: () -> Destination) -> some View {
        // Large text puts the value under the title instead of squeezing both onto one line.
        let text = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 8))
        return NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                text {
                    Text(title).foregroundStyle(Color.primary).layoutPriority(1)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    if let value { Text(value).foregroundStyle(Color.secondary).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel)).accessibilityHidden(true)
            }
            .padding(.leading, 16).padding(.trailing, edge).padding(.vertical, 6)
            // The row takes whatever height the page hands it.
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(GroupedRowStyle(position: position, separatorInset: 62))
        .accessibilityIdentifier(id)
        .stretch(22)
    }

    private var displaySettings: some View {
        Form {
            Section {
                NavigationLink { ReaderSettingsView(store: store) } label: {
                    LabeledContent("译文显示", value: store.settings.reader.font.title)
                }.accessibilityIdentifier("readerSettingsLink")
                NavigationLink { AppearanceSettingsView(store: store) } label: {
                    LabeledContent("外观与颜色", value: "\(store.settings.appearance.title) · \(store.settings.accentTheme.title)")
                }.accessibilityIdentifier("appearanceSettingsLink")
            } footer: {
                Text("译文显示可调整字体、字号、间距和日语注音；外观与颜色可选择深浅色和主题色。")
            }
        }.settingsList()
            .navigationTitle("外观与阅读").navigationBarTitleDisplayMode(.inline)
    }

    private var dataSettings: some View {
        Form {
            Section {
                Toggle("复用近期译文与识字", isOn: Binding(get: { store.settings.cacheTranslations }, set: { on in
                    guard apply({ $0.cacheTranslations = on }), !on else { return }
                    Task { await TranslationPipeline.clearCaches(); await refreshCacheStats() }
                })).accessibilityIdentifier("translationCacheToggle")
                LabeledContent("译文缓存", value: "\(cacheStats.count) 条 · \(cacheStats.bytes / 1024) KB")
                LabeledContent("识字缓存", value: "\(ocrCacheStats.count) 条 · 约 \(ocrCacheStats.bytes / 1024) KB")
                LabeledContent("本次复用", value: "译文 \(cacheStats.hits) 次 · 识字 \(ocrCacheStats.hits) 次")
                Button("清除临时缓存") {
                    Task {
                        await TranslationPipeline.clearCaches()
                        await refreshCacheStats()
                        notice = "临时缓存已清除。"
                    }
                }.accessibilityIdentifier("clearTranslationCache")
            } header: { Text("翻译速度").sectionTitle() } footer: {
                Text("20 分钟内复用相同条件下的译文与识字结果。识字缓存最多 8 条，切换目标语言可继续复用；更换原文语言、方向或术语后重新识字。缓存仅存于内存，保留文字与位置，不保存图片。关闭后会立即清除缓存。")
            }
            Section {
                Toggle("保存翻译记录", isOn: Binding(get: { store.settings.saveRecentResult }, set: { on in
                    if !on && !store.history.isEmpty { historyChange = .disable }
                    else { apply { $0.saveRecentResult = on } }
                })).accessibilityIdentifier("saveRecentToggle")
                Picker("保留条数", selection: Binding(get: { store.settings.historyLimit }, set: { limit in
                    if limit < store.history.count { historyChange = .limit(limit) }
                    else { apply { $0.historyLimit = limit } }
                })) {
                    ForEach([10, 30, 100], id: \.self) { Text("\($0) 条").tag($0) }
                }.disabled(!store.settings.saveRecentResult).accessibilityIdentifier("historyLimitPicker")
                Button("清空翻译记录", role: .destructive) { historyChange = .clearAll }.disabled(store.history.isEmpty)
            } header: { Text("翻译记录 · 已保存 \(store.history.count) 条").sectionTitle() } footer: {
                Text("文字仅保存在本机，不保存截图。达到上限时移除最早的记录。删除记录前会先确认。")
            }
        }.settingsList()
            .navigationTitle("缓存与记录").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { feedback }
            .confirmationDialog(historyChangeTitle, isPresented: Binding(get: { historyChange != nil }, set: { if !$0 { historyChange = nil } }),
                                titleVisibility: .visible, presenting: historyChange) { change in
                switch change {
                case .clearAll:
                    Button("清空记录", role: .destructive) {
                        do { try store.clearRecent(); notice = "记录已清空。"; error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                case .disable:
                    Button("关闭并清空", role: .destructive) {
                        if apply({ $0.saveRecentResult = false }) { notice = "已关闭翻译记录。" }
                    }
                case .limit(let limit):
                    Button("删除较早的 \(max(store.history.count - limit, 0)) 条", role: .destructive) {
                        apply { $0.historyLimit = limit }
                    }
                }
            } message: { change in
                Text(historyChangeMessage(change))
            }
            .onAppear { notice = nil; error = nil }
            .task { await refreshCacheStats() }
    }

    private var historyChangeTitle: String {
        switch historyChange {
        case .disable: return "关闭翻译记录？"
        case .limit(let limit): return "只保留最近 \(limit) 条？"
        case .clearAll, nil: return "清空全部翻译记录？"
        }
    }

    private func historyChangeMessage(_ change: HistoryChange) -> String {
        let count = store.history.count
        switch change {
        case .clearAll: return "已保存的 \(count) 条记录会被删除，无法恢复。"
        case .disable: return "关闭后不再保存新的翻译，已保存的 \(count) 条记录也会被删除，无法恢复。"
        case .limit(let limit): return "较早的 \(max(count - limit, 0)) 条记录会被删除，无法恢复。"
        }
    }

    private var basicSettings: some View {
        Form {
            Section {
                Picker("翻译服务", selection: Binding(get: { store.settings.translationService }, set: { service in
                    do { try store.updateQuickEngine(service); error = nil }
                    catch { self.error = error.localizedDescription }
                })) {
                    ForEach(TranslationService.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("translationServicePicker")
                NavigationLink { LanguagePacksView(source: store.settings.source, target: store.settings.target) } label: {
                    Label("本机语言包", systemImage: "arrow.down.circle")
                }.accessibilityIdentifier("languagePacksLink")
            } header: { Text("翻译引擎").sectionTitle() } footer: {
                Text("系统翻译仅用于 App 内快速模式。操作按钮使用 API；专业和识图模式也需要 API。")
            }

            Section {
                Picker("原文语言", selection: setting(\.source)) {
                    ForEach(SourceLanguage.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("settingsSourceLanguagePicker")
                Picker("目标语言", selection: setting(\.target)) {
                    ForEach(TargetLanguage.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("settingsTargetLanguagePicker")
                NavigationLink { LanguagePriorityView(store: store) } label: {
                    LabeledContent("语言优先级", value: store.settings.smartTarget
                        ? store.settings.languagePriority.map(\.title).joined(separator: " › ") : "关闭")
                }.accessibilityIdentifier("languagePriorityLink")
                Picker("表达风格", selection: setting(\.tone)) {
                    ForEach(TranslationTone.allCases) { Text($0.title).tag($0) }
                }.disabled(store.settings.translationService == .system)
            } header: { Text("语言与表达").sectionTitle() } footer: {
                Text("支持中文、英语和日语。自动识别可处理混合语言，原文语言也用于辅助识字。自动识别到原文已经是目标语言时，按语言优先级改译成另一种语言。")
            }
            Section {
                Picker("默认模式", selection: setting(\.mode)) {
                    ForEach(store.settings.allowedModes) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("defaultModePicker")
                Toggle("过滤屏幕控件", isOn: setting(\.cleanScreenText))
                    .accessibilityIdentifier("cleanScreenTextToggle")
                Toggle("原图直译", isOn: setting(\.imageOverlay))
                    .accessibilityIdentifier("imageOverlayToggle")
            } header: { Text("模式与识字").sectionTitle() } footer: {
                Text("快速模式完整简译；专业模式保留段落、列表及价格关系；识图模式解释文字与画面。也可在翻译页切换。原图直译把截图译文叠在原文位置；开启后，AI 快速模式会多用一些 token，也会慢一点。")
            }
            Section {
                Toggle("每次运行时选择模式", isOn: setting(\.askModeInShortcuts))
                    .accessibilityIdentifier("askModeInShortcutsToggle").disabled(store.settings.translationService == .system)
            } header: { Text("操作按钮").sectionTitle() }
            if store.settings.translationService == .api {
                Section {
                    TextField("例如：checkout → payment", text: $glossary, axis: .vertical)
                        .lineLimit(3...7).focused($editing).accessibilityIdentifier("glossaryField")
                    Text("\(glossary.count) / 4000 字符").font(.caption.monospacedDigit())
                        .foregroundStyle(glossary.count > 4_000 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                } header: { Text("术语表").sectionTitle() } footer: {
                    Text("收起键盘或离开本页时自动保存。")
                }
            }
        }
        .settingsList()
        .navigationTitle("翻译偏好").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { feedback }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { editing = false } }
        }
        .onChange(of: editing) { _, focused in if !focused { commitGlossary() } }
        .onAppear { glossary = store.settings.glossary; notice = nil; error = nil }
        .onDisappear { commitGlossary() }
    }

    private var feedback: some View { SettingsFeedback(error: error, notice: notice) }

    /// Binding that saves the setting as soon as it changes.
    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in apply { $0[keyPath: keyPath] = value } })
    }

    @discardableResult
    private func apply(_ change: (inout AppSettings) -> Void) -> Bool {
        var value = store.settings
        change(&value)
        guard value != store.settings else { return true }
        do { try store.save(value, keys: [:]); error = nil; return true }
        catch { self.error = error.localizedDescription; notice = nil; return false }
    }

    private func commitGlossary() {
        guard glossary != store.settings.glossary else { return }
        apply { $0.glossary = glossary }
    }

    private func refreshCacheStats() async {
        cacheStats = await TranslationCache.shared.statistics()
        ocrCacheStats = await OCRCache.shared.statistics()
    }
}
