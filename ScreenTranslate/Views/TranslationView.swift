import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct TranslationView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: SettingsStore
    @StateObject private var model: TranslationViewModel
    @State private var photo: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showRecent = false
    @State private var retryVisualRequested = false
    @State private var swapAngle = 0.0
    @State private var swapCount = 0
    @FocusState private var editing: Bool
    @ScaledMetric(relativeTo: .body) private var editorHeight = 230

    private var sourceLanguage: Binding<SourceLanguage> {
        Binding(get: { store.settings.source }, set: { updateLanguages(source: $0, target: store.settings.target) })
    }
    private var targetLanguage: Binding<TargetLanguage> {
        Binding(get: { store.settings.target }, set: { updateLanguages(source: store.settings.source, target: $0) })
    }
    private var hasInput: Bool { model.imageData != nil || !model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasContent: Bool { model.imageData != nil || !model.text.isEmpty }
    private var visualMode: Bool { store.settings.mode == .visual }
    private var translationMode: Binding<TranslationMode> {
        Binding(get: { store.settings.mode }, set: {
            do { try store.updateMode($0) } catch { model.error = error.localizedDescription }
        })
    }

    init(store: SettingsStore) {
        self.store = store
        let model = TranslationViewModel(store: store)
        #if DEBUG
        if DebugFixtures.enabled && ProcessInfo.processInfo.arguments.contains("--fixture-image") {
            try? model.acceptImage(DebugFixtures.image())
        }
        #endif
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        languageControls
                        Divider().padding(.bottom, 20)
                        modeControls
                        inputArea
                        if let error = model.error {
                            ErrorBanner(message: error).padding(.top, 20).id("translation-error")
                        }
                        if let result = model.result {
                            Divider().padding(.vertical, 24)
                            ResultContent(result: result).id("translation-result")
                        }
                        if model.imageData != nil, !visualMode, store.settings.translationService == .api,
                           model.result?.uncertainOCR == true || model.ocrWarning != nil || model.error == TranslationError.noText.localizedDescription {
                            Button("用识图模式重试") {
                                retryVisualRequested = true
                                translationMode.wrappedValue = .visual
                            }.font(.subheadline).frame(minHeight: 44).disabled(model.busy)
                                .accessibilityIdentifier("retryVisualMode")
                            Text("将图片发送给 AI，解析文字与画面。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively).background(Theme.canvas)
                .onChange(of: model.result?.id) { _, id in
                    if id != nil { DispatchQueue.main.async { withAnimation { proxy.scrollTo("translation-result", anchor: .top) } } }
                }
                .onChange(of: model.error) { _, error in
                    if error != nil { DispatchQueue.main.async { withAnimation { proxy.scrollTo("translation-error", anchor: .center) } } }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { translationControls }
            .navigationTitle("读屏").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.refreshRecent(); showRecent = true } label: { Image(systemName: "clock") }
                        .foregroundStyle(.secondary).accessibilityLabel("翻译记录").accessibilityIdentifier("recentResultButton")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { editing = false } }
            }
            .onChange(of: photo) { _, item in if let item { model.loadPhoto(item) } }
            .onChange(of: store.settings.source) { _, _ in model.invalidateTranslation() }
            .onChange(of: store.settings.target) { _, _ in model.invalidateTranslation() }
            .onChange(of: store.settings.mode) { _, _ in
                model.modeChanged()
                if retryVisualRequested { retryVisualRequested = false; model.translate() }
            }
            .onChange(of: store.settings.quickEngine) { _, _ in model.invalidateTranslation() }
            .sheet(item: $model.systemRequest) { request in
                SystemTranslationView(request: request, completed: { model.completeSystem($0, outcome: $1) }, cancel: model.cancel)
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
                switch result { case .success(let url): model.loadFile(url); case .failure(let error): model.error = error.localizedDescription }
            }
            .sheet(isPresented: $showRecent) { RecentResultView(store: store) }
        }
    }

    private var languageControls: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(SourceLanguage.allCases) { language in
                    Button(language.title) { sourceLanguage.wrappedValue = language }
                }
            } label: {
                languageLabel(store.settings.source.title, caption: "原文", alignment: .leading)
            }.accessibilityLabel("原文语言：\(store.settings.source.title)")
                .accessibilityValue(store.settings.source.title).accessibilityIdentifier("sourceLanguagePicker")
            Button {
                do {
                    try withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                        try store.swapLanguages(); swapAngle += 180; swapCount += 1
                    }
                } catch { model.error = error.localizedDescription }
            } label: {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 15, weight: .medium))
                    .rotationEffect(.degrees(reduceMotion ? 0 : swapAngle))
                    .frame(width: 42, height: 42).background(Theme.background, in: Circle())
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("交换语言").accessibilityIdentifier("swapLanguagesButton")
                .disabled(store.settings.source == .automatic)
                .sensoryFeedback(.selection, trigger: swapCount)
            Menu {
                ForEach(TargetLanguage.allCases) { language in
                    Button(language.title) { targetLanguage.wrappedValue = language }
                }
            } label: {
                languageLabel(store.settings.target.title, caption: "译文", alignment: .trailing)
            }.accessibilityLabel("目标语言：\(store.settings.target.title)")
                .accessibilityValue(store.settings.target.title).accessibilityIdentifier("targetLanguagePicker")
        }.tint(.primary).padding(.vertical, 12).disabled(model.busy)
    }

    private func languageLabel(_ title: String, caption: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            Text(caption).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(title).font(.body.weight(.medium)).contentTransition(.opacity)
                Image(systemName: "chevron.down").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, minHeight: 46, alignment: alignment == .leading ? .leading : .trailing)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: title)
    }

    private var modeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.settings.translationService == .api {
                Picker("模式", selection: translationMode) {
                    ForEach(store.settings.allowedModes) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("translationModePicker")
                Text(store.settings.mode.detail).font(.caption).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.settings.mode)
            } else {
                HStack {
                    Text("快速翻译").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("系统翻译").font(.caption).foregroundStyle(.secondary)
                }.frame(minHeight: 32).accessibilityIdentifier("systemServiceSummary")
            }
            if store.settings.mode == .visual {
                Text("识图模式会发送图片，请选择支持图片输入的模型。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.bottom, 24).disabled(model.busy)
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let preview = model.preview {
                Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 180)
                    .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("已选图片")
                if visualMode {
                    Button("移除图片", role: .destructive) { model.clear(); photo = nil }
                        .font(.subheadline).frame(minHeight: 44).disabled(model.busy)
                }
            }
            if visualMode && model.imageData == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("识别图片").font(.title3)
                    Text("选择照片或截图开始翻译。").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: editorHeight, alignment: .topLeading).padding(.top, 8)
            }
            if !visualMode {
            ZStack(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text(model.imageData == nil ? "输入或粘贴文字…" : "识别图片或输入文字…")
                        .font(.title3).foregroundStyle(.secondary).padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.text).font(.system(size: 18)).lineSpacing(5)
                    .textInputAutocapitalization(.sentences).autocorrectionDisabled()
                    .frame(height: model.imageData == nil ? editorHeight : editorHeight * 0.65)
                    .padding(.trailing, hasContent ? 36 : 0)
                    .scrollContentBackground(.hidden).focused($editing).disabled(model.busy)
                    .accessibilityLabel("原文").accessibilityIdentifier("sourceEditor")
            }.overlay(alignment: .topTrailing) {
                if hasContent {
                    Button { model.clear(); photo = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .foregroundStyle(.secondary).buttonStyle(.plain).disabled(model.busy)
                        .accessibilityLabel("清空原文").accessibilityIdentifier("clearInputButton")
                }
            }
            if let warning = model.ocrWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
            if model.imageData != nil {
                Button("核对识别文字") { editing = false; model.recognize() }
                    .font(.subheadline).frame(minHeight: 44).disabled(model.busy).accessibilityIdentifier("recognizeOnly")
            }
            }
            HStack(spacing: 16) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("照片", systemImage: "photo").frame(minHeight: 44)
                }.accessibilityIdentifier("choosePhoto")
                Button { showFiles = true } label: { Image(systemName: "folder").frame(width: 44, height: 44) }
                    .accessibilityLabel("从文件导入图片").accessibilityIdentifier("chooseFile")
                Spacer(minLength: 0)
                if !model.text.isEmpty {
                    Text("\(model.text.count) / 16000").font(.caption2.monospacedDigit())
                        .foregroundStyle(model.text.count > 16000 ? Color.orange : Color.secondary)
                }
            }.font(.subheadline).foregroundStyle(.secondary).buttonStyle(.plain).disabled(model.busy)
        }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.04), lineWidth: 1))
    }

    private var translationControls: some View {
        Group {
            if model.busy {
                HStack {
                    ProgressView()
                    TimelineView(.periodic(from: model.startedAt, by: 1)) { context in
                        Text("\(model.phase.title) · \(max(0, Int(context.date.timeIntervalSince(model.startedAt)))) 秒")
                    }
                    Spacer(); Button("取消") { model.cancel() }.accessibilityIdentifier("cancelTranslation")
                }
                    .font(.subheadline).frame(minHeight: 52)
            } else {
                Button { editing = false; model.translate() } label: {
                    Text(visualMode ? "解析图片" : (model.imageData != nil && model.text.isEmpty ? "识字并翻译" : "翻译"))
                        .font(.body.weight(.semibold)).foregroundStyle(hasInput ? theme.onAccent : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .background(hasInput ? theme.accent : Theme.background, in: RoundedRectangle(cornerRadius: 10))
                    .disabled(!hasInput || (visualMode && model.imageData == nil)).accessibilityIdentifier("translateButton")
            }
        }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16).background(Theme.canvas)
    }

    private func updateLanguages(source: SourceLanguage, target: TargetLanguage) {
        do { try store.updateLanguages(source: source, target: target) } catch { model.error = error.localizedDescription }
    }
}
