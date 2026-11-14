import SwiftUI

/// 设置 › AI 大模型: the model in use, the providers that were set up, and
/// the way to add more.
struct AIModelsView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var store: SettingsStore
    @State private var showSwitcher = false
    @State private var showAdd = false
    @State private var showHelp = false
    @State private var notice: String?
    @State private var error: String?

    private var settings: AppSettings { store.settings }
    private var activeModel: String { settings.configuration.model.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            Section {
                ProviderHeader(provider: settings.provider, name: settings.configuration.name, caption: "读屏正在用",
                               title: activeModel.isEmpty ? "还没有选模型" : activeModel,
                               detail: settings.displayName(for: settings.activeID))
                    // The line under the card runs its whole width, not from the text beside the icon.
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .accessibilityIdentifier("activeModelCard")
                Button("换模型") { showSwitcher = true }.accessibilityIdentifier("switchModelButton")
            } footer: { activeFooter }

            Section {
                ForEach(store.listedProviderIDs, id: \.self) { id in
                    NavigationLink { ProviderDetailView(store: store, entryID: id) } label: { providerLabel(id) }
                        .accessibilityIdentifier("provider-" + id)
                }
                Button { showAdd = true } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.accent)
                            .frame(width: 34, height: 34)
                            .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .accessibilityHidden(true)
                        Text("添加供应商").foregroundStyle(Color.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel)).accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("addProviderButton")
            } header: { Text("供应商").sectionTitle() } footer: {
                Text("每个供应商各自保存密钥、地址和模型。点开可以增删模型，或改接口格式和思考强度。")
            }
        }
        .settingsList(icons: true)
        .navigationTitle("AI 大模型").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { SettingsFeedback(error: error, notice: notice) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
                    .accessibilityLabel("说明").accessibilityIdentifier("aiHelpButton")
            }
        }
        .sheet(isPresented: $showSwitcher) { ModelSwitcherView(store: store) { notice = $0; error = nil } }
        .sheet(isPresented: $showAdd) { AddProviderView(store: store) { notice = $0; error = nil } }
        .sheet(isPresented: $showHelp) { AIHelpView() }
        .onAppear { store.refreshKeys() }
    }

    @ViewBuilder private var activeFooter: some View {
        if !store.keyedIDs.contains(settings.activeID) {
            Label("这个供应商还没有填 API Key，填好后才能翻译。", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange).accessibilityIdentifier("missingKeyHint")
        } else if settings.translationService == .system {
            Text("翻译服务目前选的是“系统翻译”：App 内的快速翻译不经过这里的模型，操作按钮仍然用它。")
        }
    }

    private func providerLabel(_ id: String) -> some View {
        let keyed = store.keyedIDs.contains(id)
        let count = settings.savedModels(for: id).count
        return ProviderRowLabel(provider: AIProvider.kind(of: id), name: settings.configurations[id]?.name,
                                title: settings.displayName(for: id),
                                detail: keyed ? "\(count) 个模型" : "\(count) 个模型 · 未填密钥",
                                detailColor: keyed ? .secondary : .orange,
                                tag: id == settings.activeID ? "正在用" : nil)
    }
}

/// 换模型: every kept model of every provider; one tap puts it in use.
struct ModelSwitcherView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SettingsStore
    var onSwitch: (String) -> Void
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.listedProviderIDs, id: \.self) { id in section(id) }
            }
            .settingsList()
            .navigationTitle("换模型").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { SettingsFeedback(error: error, notice: nil) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.accessibilityIdentifier("closeModelSwitcher")
                }
            }
        }
        .onAppear { store.refreshKeys() }
    }

    private func section(_ id: String) -> some View {
        let kind = AIProvider.kind(of: id)
        let keyed = store.keyedIDs.contains(id)
        let models = store.settings.savedModels(for: id)
        return Section {
            ForEach(models) { model in
                Button { choose(id, model.id) } label: {
                    HStack {
                        ModelLabel(id: model.id,
                                   detail: kind.models.first { $0.id == model.id }.map { $0.title + " · " + $0.detail },
                                   dimmed: !keyed)
                        Spacer()
                        if store.settings.isInUse(model: model.id, of: id) {
                            Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(theme.accent)
                                .accessibilityLabel("正在用")
                        }
                    }
                }
                .disabled(!keyed)
                .accessibilityIdentifier("switch-\(id)-\(model.id)")
            }
            if models.isEmpty {
                Text("还没有模型，到这个供应商的页面里添加。").font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            Text(store.settings.displayName(for: id)).sectionTitle()
        } footer: {
            if !keyed { Text("还没有填 API Key，暂时不能选。") }
        }
    }

    private func choose(_ id: String, _ model: String) {
        do {
            try store.change { $0.activate(id, model: model) }
            onSwitch("已换成 \(store.settings.displayName(for: id)) 的 \(model)。")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct AIHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                item("供应商是什么", "提供大模型接口的服务商，比如 Claude、ChatGPT、DeepSeek。读屏自己不提供模型：你在服务商那里申请 API Key 填到这里，翻译时由读屏直接向它发请求，费用由服务商按用量收取。")
                item("怎么添加", "点“添加供应商”，选一家，填上 API Key 就可以。列表里没有的服务用“自定义”，填它的 API 地址、接口格式和模型 ID。")
                item("换模型", "一个供应商下面可以留几个模型。“读屏正在用”的那一个负责翻译；点“换模型”可以在所有填了密钥的供应商之间切换。")
                item("接口格式和思考强度", "点开某个模型可以单独设置。接口格式照服务商文档选，测试连接能通就对；思考强度越高，译得越慢、费用越高，日常翻译用“自动”即可。")
                item("会发送什么", "快速和专业模式只发送文字；识图模式会发送压缩后的图片。API Key 只保存在本机钥匙串里。")
            }
            .settingsList()
            .navigationTitle("说明").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.accessibilityIdentifier("closeAIHelp") }
            }
        }
    }

    private func item(_ title: String, _ text: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
