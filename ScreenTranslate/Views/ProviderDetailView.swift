import SwiftUI

/// One provider: its key and address, and the models kept under it.
struct ProviderDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SettingsStore
    let entryID: String
    @State private var showCredentials = false
    @State private var showAddModel = false
    @State private var confirmDelete = false
    @State private var notice: String?
    @State private var error: String?

    private var kind: AIProvider { AIProvider.kind(of: entryID) }
    private var configuration: ProviderConfiguration { store.settings.configuration(for: entryID) }
    private var displayName: String { store.settings.displayName(for: entryID) }
    private var isActive: Bool { store.settings.activeID == entryID }
    private var hasKey: Bool { store.keyedIDs.contains(entryID) }
    private var host: String {
        let text = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return URLComponents(string: text)?.host ?? (text.isEmpty ? "未填写" : text)
    }

    var body: some View {
        List {
            Section {
                ProviderHeader(provider: kind, name: configuration.name, title: displayName,
                               detail: kind == .custom ? host : kind.subtitle)
            }
            Section {
                // Both rows open the same editor.
                Button { showCredentials = true } label: {
                    ValueRow(title: "API Key", value: hasKey ? "已填写" : "未填写", warn: !hasKey)
                }
                .accessibilityIdentifier("editCredentialsButton")
                Button { showCredentials = true } label: { ValueRow(title: "API 地址", value: host) }
                    .accessibilityIdentifier("editAddressButton")
            } header: { Text("密钥与地址").sectionTitle() } footer: {
                Text(kind == .custom ? "点一下修改名称、密钥或地址。" : kind.setupNote)
            }
            Section {
                ForEach(store.settings.savedModels(for: entryID)) { model in
                    NavigationLink {
                        ModelDetailView(store: store, entryID: entryID, modelID: model.id)
                    } label: { modelLabel(model) }
                    .accessibilityIdentifier("model-" + model.id)
                }
                Button("添加模型") { showAddModel = true }.accessibilityIdentifier("addModelButton")
            } header: { Text("模型").sectionTitle() } footer: {
                Text("点开模型可改接口格式、思考强度，或设为正在用。")
            }
            Section {
                ExternalLinkRow(title: kind == .custom ? "OpenAI 兼容接口说明" : "\(kind.title) 官方文档",
                                url: kind.documentationURL)
            }
            Section {
                Button("删除这个供应商", role: .destructive) { confirmDelete = true }
                    .disabled(isActive).accessibilityIdentifier("deleteProviderButton")
            } footer: {
                if isActive { Text("正在用的供应商不能删除。先用“换模型”换到别的供应商。") }
            }
        }
        .settingsList()
        .navigationTitle(displayName).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { SettingsFeedback(error: error, notice: notice) }
        .sheet(isPresented: $showCredentials) {
            ProviderCredentialsEditor(store: store, entryID: entryID) { notice = $0; error = nil }
        }
        .sheet(isPresented: $showAddModel) {
            AddModelView(store: store, entryID: entryID) { notice = $0; error = nil }
        }
        .confirmationDialog("删除 \(displayName)？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { remove() }
        } message: {
            Text("它的 API Key、地址和模型设置都会从本机移除，无法恢复。")
        }
        .onAppear { store.refreshKeys() }
    }

    private func modelLabel(_ model: SavedModel) -> some View {
        let preset = kind.models.first { $0.id == model.id }
        var parts: [String] = []
        if let preset { parts.append(preset.title + " · " + preset.detail) }
        parts.append(model.style.displayName)
        if let reasoning = model.reasoning { parts.append("思考" + reasoning.title) }
        return ModelLabel(id: model.id, detail: parts.joined(separator: " · "),
                          tag: store.settings.isInUse(model: model.id, of: entryID) ? "正在用" : nil)
    }

    private func remove() {
        do { try store.removeProvider(entryID); dismiss() }
        catch { self.error = error.localizedDescription; notice = nil }
    }
}

/// Edits a provider's key and address. Nothing changes until 保存.
struct ProviderCredentialsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SettingsStore
    let entryID: String
    var onSaved: (String) -> Void
    @State private var name = ""
    @State private var key = ""
    @State private var baseURL = ""
    @State private var loaded = false
    @State private var error: String?
    @FocusState private var editing: Bool

    private var kind: AIProvider { AIProvider.kind(of: entryID) }
    private var saved: ProviderConfiguration { store.settings.configuration(for: entryID) }
    private var changed: Bool {
        key != store.apiKey(for: entryID) || baseURL != saved.baseURL || name != (saved.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if kind == .custom {
                    Section {
                        TextField("自定义 API", text: $name).autocorrectionDisabled().focused($editing)
                            .accessibilityIdentifier("providerNameField")
                    } header: { Text("名称").sectionTitle() }
                }
                Section {
                    APIKeyField(key: $key, focus: $editing)
                } header: { Text("API Key").sectionTitle() } footer: {
                    Text("密钥只保存在本机钥匙串中。清空后保存会删除已存的密钥。")
                }
                Section {
                    TextField("https://…", text: $baseURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($editing).accessibilityLabel("API 地址").accessibilityIdentifier("apiURLField")
                    if kind != .custom, baseURL != kind.defaultURL {
                        Button("恢复官方地址") { baseURL = kind.defaultURL }
                    }
                } header: { Text("API 地址").sectionTitle() } footer: {
                    Text(kind == .custom ? "服务商文档里的 API 地址，必须是 HTTPS。" : kind.setupNote)
                }
            }
            .settingsList()
            .navigationTitle("密钥与地址").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { SettingsFeedback(error: error, notice: nil) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("cancelCredentialsButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }.fontWeight(.semibold).disabled(!changed)
                        .accessibilityIdentifier("saveCredentialsButton")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { editing = false } }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = saved.name ?? ""; key = store.apiKey(for: entryID); baseURL = saved.baseURL
        }
        // With unsaved edits the sheet closes only through 取消 or 保存.
        .interactiveDismissDisabled(loaded && changed)
    }

    private func save() {
        editing = false
        var address = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty { address = kind.defaultURL }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = store.settings
        value.updateConfiguration(for: entryID) {
            $0.baseURL = address
            if kind == .custom { $0.name = label.isEmpty ? nil : label }
        }
        do {
            _ = try APIClient.endpoint(configuration: value.configuration(for: entryID))
            try store.save(value, keys: [entryID: key])
            onSaved("已保存。")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Adds a model to a provider: a preset, one the account can use, or a typed id.
struct AddModelView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SettingsStore
    let entryID: String
    var onAdded: (String) -> Void
    @State private var modelID = ""
    @State private var fetched: [String] = []
    @State private var showFetched = false
    @State private var busy = false
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    @FocusState private var editing: Bool

    private var kind: AIProvider { AIProvider.kind(of: entryID) }
    private var kept: Set<String> { Set(store.settings.savedModels(for: entryID).map(\.id)) }
    private var typed: String { modelID.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var presets: [ModelPreset] { kind.models.filter { !kept.contains($0.id) } }

    var body: some View {
        NavigationStack {
            Form {
                if !presets.isEmpty {
                    Section {
                        ForEach(presets) { preset in
                            Button { add(preset.id) } label: {
                                ModelLabel(id: preset.id, detail: preset.title + " · " + preset.detail)
                            }
                            .accessibilityIdentifier("model-" + preset.id)
                        }
                    } header: { Text("常用模型").sectionTitle() }
                }
                Section {
                    TextField("模型 ID", text: $modelID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                        .accessibilityIdentifier("modelField")
                    Button("添加这个模型") { add(typed) }
                        .disabled(typed.isEmpty || kept.contains(typed))
                        .accessibilityIdentifier("addTypedModelButton")
                } header: { Text("手动填写").sectionTitle() } footer: {
                    Text(kept.contains(typed) ? "这个模型已经在列表里了。" : "照服务商文档里的模型 ID 填写。")
                }
                Section {
                    Button("获取可用模型") { fetchModels() }.accessibilityIdentifier("fetchModelsButton")
                } footer: {
                    Text("用已保存的密钥向服务商查询这个账户能用的模型。")
                }
            }
            .disabled(busy)
            .settingsList()
            .navigationTitle("添加模型").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if busy {
                        HStack { ProgressView(); Text("正在连接…"); Spacer(); Button("取消") { job?.cancel() } }
                            .font(.subheadline).padding(.horizontal, 20).padding(.vertical, 10).background(Theme.background)
                    }
                    SettingsFeedback(error: error, notice: nil)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("cancelAddModel")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { editing = false } }
            }
            .sheet(isPresented: $showFetched) {
                FetchedModelPicker(models: fetched, kept: kept) { add($0) }
            }
        }
        .onDisappear { job?.cancel() }
    }

    private func add(_ id: String) {
        editing = false
        guard !id.isEmpty, !kept.contains(id) else { return }
        do {
            try store.change {
                $0.updateConfiguration(for: entryID) { configuration in
                    // A new model starts with the format the provider's other models use.
                    configuration.upsert(SavedModel(id: id, style: configuration.style), provider: kind)
                }
            }
            onAdded("已添加 \(id)。")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func fetchModels() {
        editing = false; busy = true; error = nil
        let configuration = store.settings.configuration(for: entryID)
        let apiKey = store.apiKey(for: entryID)
        job = Task {
            defer { busy = false }
            do {
                fetched = try await TranslationPipeline().client.models(configuration: configuration, apiKey: apiKey)
                try Task.checkCancellation()
                showFetched = true
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}

/// One model: its interface format, reasoning depth, a connection test, and
/// the switches to put it in use or delete it.
struct ModelDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SettingsStore
    let entryID: String
    let modelID: String
    @State private var advanced = true
    @State private var testing = false
    @State private var outcome: Outcome?
    @State private var job: Task<Void, Never>?
    @State private var confirmDelete = false
    @State private var error: String?

    private enum Outcome: Equatable {
        case passed(TimeInterval), failed(String)
    }

    private var kind: AIProvider { AIProvider.kind(of: entryID) }
    private var model: SavedModel? { store.settings.savedModels(for: entryID).first { $0.id == modelID } }
    private var inUse: Bool { store.settings.isInUse(model: modelID, of: entryID) }
    private var hasKey: Bool { store.keyedIDs.contains(entryID) }

    var body: some View {
        List {
            Section {
                ProviderHeader(provider: kind, name: store.settings.configurations[entryID]?.name,
                               title: modelID, detail: store.settings.displayName(for: entryID))
            }
            Section {
                Picker("接口格式", selection: style) {
                    ForEach(APIStyle.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("apiStylePicker")
            } header: { Text("接口格式").sectionTitle() } footer: {
                Text("照服务商文档里写的格式选；测试连接通了就对。")
            }
            Section {
                DisclosureRow(title: "高级", isExpanded: $advanced)
                if advanced {
                    Picker("思考强度", selection: reasoning) {
                        Text("自动").tag(ReasoningEffort?.none)
                        ForEach(kind.reasoningOptions) { Text($0.title).tag(Optional($0)) }
                    }
                    .accessibilityIdentifier("reasoningPicker")
                }
            } footer: {
                if advanced {
                    Text(kind.reasoningNote + "强度越高越慢、费用越高。模型不支持所选档位时会显示服务商原话，改回自动即可。")
                }
            }
            Section {
                Button { test() } label: {
                    HStack {
                        Text("测试连接")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }
                .disabled(testing).accessibilityIdentifier("testConnectionButton")
                testStatus
            } footer: {
                Text("发送一句“Hello.”看这个模型能不能用，可能产生少量 API 费用。")
            }
            Section {
                Button { activate() } label: {
                    HStack {
                        Text(inUse ? "正在使用" : "设为正在用")
                        Spacer()
                        if inUse {
                            Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(theme.accent)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .disabled(inUse || !hasKey).accessibilityIdentifier("setActiveModelButton")
            } footer: {
                if !hasKey { Text("这个供应商还没有填 API Key，填好后才能设为正在用。") }
            }
            Section {
                Button("删除这个模型", role: .destructive) { confirmDelete = true }
                    .disabled(inUse).accessibilityIdentifier("deleteModelButton")
            } footer: {
                if inUse { Text("正在用的模型不能删除，先换到别的模型。") }
            }
        }
        .settingsList()
        .navigationTitle("模型").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { SettingsFeedback(error: error, notice: nil) }
        .confirmationDialog("删除 \(modelID)？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { remove() }
        } message: {
            Text("只是从这个供应商的列表里移除，以后可以再添加。")
        }
        .onAppear { store.refreshKeys() }
        .onDisappear { job?.cancel() }
    }

    @ViewBuilder private var testStatus: some View {
        switch outcome {
        case .passed(let seconds):
            Label(String(format: "连接正常，用时 %.1f 秒", seconds), systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(theme.accent).accessibilityIdentifier("connectionResult")
        case .failed(let message):
            Label {
                Text(message).font(.subheadline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            .accessibilityIdentifier("connectionResult")
        case nil:
            Text(testing ? "正在等服务商回复…" : "还没有测试过").font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("connectionResult")
        }
    }

    private var style: Binding<APIStyle> {
        Binding(get: { model?.style ?? .chatCompletions }, set: { value in update { $0.style = value } })
    }

    private var reasoning: Binding<ReasoningEffort?> {
        Binding(get: { model?.reasoning }, set: { value in update { $0.reasoning = value } })
    }

    /// Saves a change to this model at once; an earlier test result no longer applies.
    private func update(_ change: (inout SavedModel) -> Void) {
        guard var item = model else { return }
        change(&item)
        guard item != model else { return }
        do {
            try store.change { $0.updateConfiguration(for: entryID) { $0.upsert(item, provider: kind) } }
            error = nil; outcome = nil
        } catch { self.error = error.localizedDescription }
    }

    private func activate() {
        do { try store.change { $0.activate(entryID, model: modelID) }; error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func remove() {
        do {
            try store.change { $0.updateConfiguration(for: entryID) { $0.removeModel(modelID, provider: kind) } }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func test() {
        guard let item = model else { return }
        testing = true; outcome = nil; error = nil
        // A request reads the top-level fields, so point them at this model.
        var configuration = store.settings.configuration(for: entryID)
        configuration.model = item.id; configuration.style = item.style; configuration.reasoning = item.reasoning
        let apiKey = store.apiKey(for: entryID), base = store.settings
        job = Task {
            defer { testing = false }
            do {
                outcome = .passed(try await ConnectionCheck.run(settings: base, entryID: entryID,
                                                                configuration: configuration, apiKey: apiKey))
            } catch is CancellationError {} catch { outcome = .failed(error.localizedDescription) }
        }
    }
}
