import SwiftUI

/// 添加供应商: one list of presets, Claude, ChatGPT and DeepSeek first, plus
/// a form for any other compatible service.
struct AddProviderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SettingsStore
    var onAdded: (String) -> Void
    @State private var mode = Mode.preset
    @State private var showHelp = false

    private enum Mode: String, CaseIterable, Identifiable {
        case preset = "预设", custom = "自定义"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if mode == .preset { presets } else {
                    ProviderSetupForm(store: store, kind: .custom, finish: finish)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("添加方式", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10)
                .background(Theme.background).accessibilityIdentifier("addProviderMode")
            }
            .navigationTitle("添加供应商").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("cancelAddProvider")
                }
                if mode == .preset {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }
                            .accessibilityLabel("说明")
                    }
                }
            }
            .sheet(isPresented: $showHelp) { AIHelpView() }
        }
        .onAppear { store.refreshKeys() }
    }

    /// The default provider is listed from the first launch. Until it has a key
    /// or settings of its own it can still be set up from this page.
    private func isSetUp(_ provider: AIProvider) -> Bool {
        let id = provider.rawValue
        return store.listedProviderIDs.contains(id)
            && (store.keyedIDs.contains(id) || store.settings.configurations[id] != nil)
    }

    private var presets: some View {
        List {
            Section {
                ForEach(AIProvider.presets) { provider in
                    if isSetUp(provider) {
                        HStack {
                            ProviderRowLabel(provider: provider, title: provider.title, detail: provider.subtitle)
                            Spacer()
                            Text("已添加").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .opacity(0.55)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("preset-" + provider.rawValue)
                    } else {
                        NavigationLink {
                            ProviderSetupForm(store: store, kind: provider, finish: finish)
                        } label: {
                            ProviderRowLabel(provider: provider, title: provider.title, detail: provider.subtitle,
                                             tag: provider.isRecommended ? "推荐" : nil)
                        }
                        .accessibilityIdentifier("preset-" + provider.rawValue)
                    }
                }
            } footer: {
                Text("选一家，填上它的 API Key。没有列出的服务，用上面的“自定义”添加。")
            }
        }
        .settingsList(icons: true)
    }

    private func finish(_ message: String) {
        onAdded(message)
        dismiss()
    }
}

/// Key, models and address for one new provider.
struct ProviderSetupForm: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var store: SettingsStore
    let kind: AIProvider
    var finish: (String) -> Void

    @State private var name = ""
    @State private var key = ""
    @State private var baseURL = ""
    @State private var style = APIStyle.chatCompletions
    @State private var chosen: Set<String> = []
    @State private var modelID = ""
    @State private var fetched: [String] = []
    @State private var showFetched = false
    @State private var advanced = false
    @State private var loaded = false
    @State private var busy = false
    @State private var notice: String?
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    @FocusState private var editing: Bool

    private var isCustom: Bool { kind == .custom }
    private var modelIDs: [String] {
        if isCustom {
            let id = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? [] : [id]
        }
        return kind.models.map(\.id).filter(chosen.contains)
    }
    private var canAdd: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !modelIDs.isEmpty
            && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What would be saved; the first chosen model becomes the provider's model in use.
    private var draft: ProviderConfiguration {
        var value = ProviderConfiguration(provider: kind)
        value.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        value.style = style
        value.reasoning = nil
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.name = isCustom && !label.isEmpty ? label : nil
        value.models = modelIDs.map { SavedModel(id: $0, style: style) }
        value.model = modelIDs.first ?? ""
        return value
    }

    var body: some View {
        Form {
            if isCustom { customFields } else { presetFields }
            Section {
                Button("测试连接") { testConnection() }.accessibilityIdentifier("testConnectionButton")
            } footer: {
                Text("用上面填写的内容发送一句“Hello.”，可能产生少量 API 费用。")
            }
            .disabled(busy)
            if !isCustom {
                Section { ExternalLinkRow(title: "\(kind.title) 官方文档", url: kind.documentationURL) }
            }
        }
        .settingsList()
        .navigationTitle(isCustom ? "添加供应商" : kind.title).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { feedback }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加") { add() }.fontWeight(.semibold).disabled(busy || !canAdd)
                    .accessibilityIdentifier("confirmAddProviderButton")
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { editing = false } }
        }
        .sheet(isPresented: $showFetched) {
            FetchedModelPicker(models: fetched) { modelID = $0 }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            baseURL = kind.defaultURL; style = kind.defaultStyle
            chosen = Set(kind.models.map(\.id))
        }
        .onDisappear { job?.cancel() }
        // Typed details are not lost to a stray swipe; 取消 still closes the sheet.
        .interactiveDismissDisabled(busy || !(key.isEmpty && name.isEmpty && modelID.isEmpty))
    }

    @ViewBuilder private var presetFields: some View {
        Section {
            ProviderHeader(provider: kind, title: kind.title, detail: kind.subtitle)
        }
        Section {
            APIKeyField(key: $key, focus: $editing)
            if let keyURL = kind.keyURL { ExternalLinkRow(title: "去 \(kind.title) 控制台申请密钥", url: keyURL) }
        } header: { Text("API Key").sectionTitle() } footer: {
            Text("密钥只保存在本机钥匙串中。")
        }
        .disabled(busy)
        Section {
            ForEach(kind.models) { model in
                Button { toggle(model.id) } label: {
                    HStack {
                        ModelLabel(id: model.id, detail: model.title + " · " + model.detail)
                        Spacer()
                        Image(systemName: chosen.contains(model.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(chosen.contains(model.id) ? theme.accent : Color(uiColor: .tertiaryLabel))
                    }
                }
                .accessibilityIdentifier("model-" + model.id)
                .accessibilityAddTraits(chosen.contains(model.id) ? .isSelected : [])
            }
        } header: { Text("模型").sectionTitle() } footer: {
            Text("勾上的模型会一起加入，排在最前的那个先用。以后可以在供应商页面里增删。")
        }
        .disabled(busy)
        Section {
            DisclosureRow(title: "高级", isExpanded: $advanced)
            if advanced {
                addressField
                stylePicker
            }
        } footer: {
            Text(kind.setupNote)
        }
        .disabled(busy)
    }

    @ViewBuilder private var customFields: some View {
        Section {
            TextField("名称（可不填）", text: $name).autocorrectionDisabled().focused($editing)
                .accessibilityIdentifier("providerNameField")
            addressField
            stylePicker
        } header: { Text("服务").sectionTitle() } footer: {
            Text("填服务商文档里的 API 地址，一般以 /v1 结尾，必须是 HTTPS。接口格式照文档选；测试连接通了就对。")
        }
        .disabled(busy)
        Section {
            APIKeyField(key: $key, focus: $editing)
        } header: { Text("API Key").sectionTitle() } footer: {
            Text("密钥只保存在本机钥匙串中。")
        }
        .disabled(busy)
        Section {
            TextField("模型 ID", text: $modelID)
                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                .accessibilityIdentifier("modelField")
            Button("获取可用模型") { fetchModels() }.accessibilityIdentifier("fetchModelsButton")
        } header: { Text("模型").sectionTitle() } footer: {
            Text("直接填模型 ID，或在填好地址和密钥后从服务返回的列表里选。")
        }
        .disabled(busy)
    }

    private var addressField: some View {
        TextField("https://…", text: $baseURL)
            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($editing).accessibilityLabel("API 地址").accessibilityIdentifier("apiURLField")
    }

    private var stylePicker: some View {
        Picker("接口格式", selection: $style) {
            ForEach(APIStyle.allCases) { Text($0.displayName).tag($0) }
        }
        .accessibilityIdentifier("apiStylePicker")
    }

    private var feedback: some View {
        VStack(spacing: 0) {
            if busy {
                HStack { ProgressView(); Text("正在连接…"); Spacer(); Button("取消") { job?.cancel() } }
                    .font(.subheadline).padding(.horizontal, 20).padding(.vertical, 10).background(Theme.background)
            }
            SettingsFeedback(error: error, notice: notice)
        }
    }

    private func toggle(_ id: String) {
        if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) }
    }

    private func add() {
        editing = false
        let value = draft
        do {
            let title = isCustom ? (value.name ?? kind.title) : kind.title
            let result = try store.addProvider(kind, configuration: value, key: key)
            finish(result.activated ? "已添加 \(title)，现在用它翻译。" : "已添加 \(title)。要用它，点“换模型”。")
        } catch { self.error = error.localizedDescription; notice = nil }
    }

    private func fetchModels() {
        editing = false; busy = true; error = nil; notice = nil
        let value = draft, apiKey = key
        job = Task {
            defer { busy = false }
            do {
                fetched = try await TranslationPipeline().client.models(configuration: value, apiKey: apiKey)
                try Task.checkCancellation()
                showFetched = true
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }

    private func testConnection() {
        editing = false; busy = true; error = nil; notice = nil
        let value = draft, apiKey = key, base = store.settings
        job = Task {
            defer { busy = false }
            do {
                guard !value.model.isEmpty else { throw TranslationError.missingModel }
                let seconds = try await ConnectionCheck.run(settings: base, entryID: kind.rawValue,
                                                            configuration: value, apiKey: apiKey)
                notice = String(format: "连接正常，用时 %.1f 秒。点“添加”保存。", seconds)
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}

/// Model ids returned by the service, with search.
struct FetchedModelPicker: View {
    @Environment(\.dismiss) private var dismiss
    var models: [String]
    /// Ids that are already kept; they are shown as added.
    var kept: Set<String> = []
    var choose: (String) -> Void
    @State private var query = ""

    private var shown: [String] {
        query.isEmpty ? models : models.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shown, id: \.self) { model in
                        Button { choose(model); dismiss() } label: {
                            HStack {
                                Text(model).foregroundStyle(kept.contains(model) ? Color.secondary : Color.primary)
                                Spacer()
                                if kept.contains(model) { Text("已添加").font(.subheadline).foregroundStyle(Color.secondary) }
                            }
                        }
                        .disabled(kept.contains(model))
                        .accessibilityIdentifier("model-" + model)
                    }
                } header: { Text("账户返回的模型").sectionTitle() }
            }
            .settingsList()
            .navigationTitle("选择模型").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索模型")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
        }
    }
}
