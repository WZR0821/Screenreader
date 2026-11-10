import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct TranslationView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject var store: SettingsStore
    @StateObject private var model: TranslationViewModel
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraDenied = false
    @State private var cameraStarting = false
    @State private var cameraResult: Result<Data, Error>?
    @State private var showRecent = false
    @State private var showTranslationReader = false
    @State private var historySelectionID: UUID?
    @State private var blockReview: TranslationReviewSelection?
    @State private var retryVisualRequested = false
    @State private var swapAngle = 0.0
    @State private var swapCount = 0
    @FocusState private var editing: Bool
    @ScaledMetric(relativeTo: .body) private var minimumEditorHeight = 100
    @ScaledMetric(relativeTo: .body) private var inputFontSize = 20

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
            ScrollViewReader { dashboard in
            ScrollView {
                dashboardContent
            }.accessibilityIdentifier("translationScroll")
                .scrollDismissesKeyboard(.interactively).background(Theme.background)
                .onChange(of: model.error) { _, error in
                    if error != nil { DispatchQueue.main.async { dashboard.scrollTo("translation-error", anchor: .center) } }
                }
            }
            .navigationTitle("翻译").navigationBarTitleDisplayMode(.large)
            .toolbar {
                if blockReview == nil && !showRecent && !model.showReview {
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { editing = false } }
                }
            }
            .navigationDestination(isPresented: $showTranslationReader) { translatedPage }
            .navigationDestination(item: $historySelectionID) { RecentResultDetailView(store: store, resultID: $0) }
            .onChange(of: model.result?.id) { _, id in
                // Opening the reader is a user action. A background completion must
                // never interrupt history, settings, or a sheet the user is viewing.
                if id == nil && !model.busy { showTranslationReader = false }
            }
            .onChange(of: model.busy) { _, busy in
                if !busy && model.result == nil && model.error == nil { showTranslationReader = false }
            }
            .onChange(of: photo) { _, item in
                if let item { editing = false; model.loadPhoto(item); photo = nil }
            }
            .onChange(of: store.settings.source) { _, _ in model.resetRecognition() }
            .onChange(of: store.settings.glossary) { _, _ in model.resetRecognition() }
            .onChange(of: store.settings.cleanScreenText) { _, _ in model.resetRecognition() }
            .onChange(of: store.settings.target) { _, _ in model.invalidateTranslation() }
            .onChange(of: store.settings.mode) { _, _ in
                model.modeChanged()
                if retryVisualRequested { retryVisualRequested = false; startTranslation() }
            }
            .onChange(of: store.settings.quickEngine) { _, _ in model.invalidateTranslation() }
            .onChange(of: store.history) { _, _ in model.refreshReviewedResult() }
            .sheet(isPresented: $model.showReview) {
                if let data = model.imageData, let recognized = model.recognizedOCR {
                    OCRReviewView(items: recognized.reviewItems, imageData: data, apply: model.applyReview)
                        .readerSheet()
                }
            }
            .sheet(item: $model.systemRequest) { request in
                SystemTranslationView(request: request, completed: { model.completeSystem($0, outcome: $1) }, cancel: model.cancel)
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: finishCamera) {
                CameraCaptureView { result in cameraResult = result; showCamera = false }.ignoresSafeArea()
            }
            .alert("需要相机权限", isPresented: $cameraDenied) {
                Button("前往设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("取消", role: .cancel) {}
            } message: { Text("请允许读屏使用相机，然后重新拍照。") }
            .sheet(isPresented: $showRecent) { RecentResultView(store: store).readerSheet() }
            .sheet(item: $blockReview) { selection in
                TranslationBlockReviewView(selection: selection, imageData: model.imageData, store: store,
                    pipeline: model.pipeline) { expected, updated in
                    try model.applyBlockReview(updated, expected: expected)
                }.readerSheet()
            }
        }
    }

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 16) {
                modeControls
                VStack(spacing: 0) {
                    languageControls
                    Divider().padding(.horizontal, 20)
                    expandedInput
                    composerActions
                }.background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.primary.opacity(0.04)))
                    .accessibilityElement(children: .contain).accessibilityIdentifier("translationInputPanel")
            }
            if let error = model.error { ErrorBanner(message: error).id("translation-error") }
            if model.imageData != nil, !visualMode, store.settings.translationService == .api,
               model.result?.uncertainOCR == true || model.ocrWarning != nil || model.error == TranslationError.noText.localizedDescription {
                Button("用识图模式重试") {
                    retryVisualRequested = true; translationMode.wrappedValue = .visual
                }.frame(minHeight: 44).accessibilityIdentifier("retryVisualMode")
            }
            recentTranslations
        }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
    }

    private var composerActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.busy { importActions }
            translationControls
        }.padding(.horizontal, 16).padding(.bottom, 16)
    }

    private var translatedPage: some View {
        LiveTranslationReader(model: model, store: store,
            editSource: {
                if model.busy { model.cancel() }
                editing = false; showTranslationReader = false
            },
            review: { blockReview = .init(result: $0, blockID: $1) },
            retryVisual: { retryVisualRequested = true; translationMode.wrappedValue = .visual })
    }

    private var recentResults: [TranslationResult] {
        Array(store.history.prefix(2))
    }

    private var recentTranslations: some View {
        VStack(alignment: .leading, spacing: 12) {
            let headerLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout())
            headerLayout {
                Text("最近翻译").font(.title3.weight(.semibold))
                if !typeSize.isAccessibilitySize { Spacer() }
                Button("查看全部") { editing = false; store.refreshRecent(); showRecent = true }
                    .font(.subheadline).frame(minHeight: 44).accessibilityLabel("查看全部翻译记录")
                    .accessibilityIdentifier("dashboardAllHistory")
            }
            if recentResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("还没有翻译记录").font(.subheadline)
                    Text("翻译完成后，可在这里继续阅读。").font(.footnote)
                }.foregroundStyle(.secondary).padding(.vertical, 8)
                    .accessibilityIdentifier("recentTranslationsEmpty")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentResults.enumerated()), id: \.element.id) { offset, result in
                        if offset > 0 { Divider().padding(.horizontal, 16) }
                        Button {
                            editing = false
                            if result.id == model.result?.id { showTranslationReader = true }
                            else { historySelectionID = result.id }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(result.translated).font(.body).foregroundStyle(.primary).lineLimit(2)
                                    Text(result.target + " · " + result.date.formatted(date: .omitted, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }.padding(16).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("dashboardResult-" + result.id.uuidString)
                    }
                }.background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var languageControls: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0))
            : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            Menu {
                Text("原文语言")
                ForEach(SourceLanguage.allCases) { language in
                    Button { sourceLanguage.wrappedValue = language } label: {
                        if language == store.settings.source { Label(language.title, systemImage: "checkmark") }
                        else { Text(language.title) }
                    }
                }
            } label: {
                languageLabel(store.settings.source.title, caption: "原文语言")
            }.buttonStyle(.plain).accessibilityLabel("原文语言：\(store.settings.source.title)")
                .accessibilityValue(store.settings.source.title).accessibilityIdentifier("sourceLanguagePicker")
            Button {
                do {
                    try withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                        try store.swapLanguages(); swapAngle += 180; swapCount += 1
                    }
                } catch { model.error = error.localizedDescription }
            } label: {
                Image(systemName: typeSize.isAccessibilitySize ? "arrow.up.arrow.down" : "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .medium))
                    .rotationEffect(.degrees(reduceMotion ? 0 : swapAngle))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
                    .background(Theme.background, in: Circle())
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("交换语言").accessibilityIdentifier("swapLanguagesButton")
                .accessibilityHint(store.settings.source == .automatic ? "请先选择原文语言" : "交换原文和目标语言")
                .disabled(store.settings.source == .automatic)
                .sensoryFeedback(.selection, trigger: swapCount)
            Menu {
                Text("目标语言")
                ForEach(TargetLanguage.allCases) { language in
                    Button { targetLanguage.wrappedValue = language } label: {
                        if language == store.settings.target { Label(language.title, systemImage: "checkmark") }
                        else { Text(language.title) }
                    }
                }
            } label: {
                languageLabel(store.settings.target.title, caption: "译为")
            }.buttonStyle(.plain).accessibilityLabel("目标语言：\(store.settings.target.title)")
                .accessibilityValue(store.settings.target.title).accessibilityIdentifier("targetLanguagePicker")
        }.padding(.horizontal, 12).padding(.vertical, 10).tint(theme.accent)
            .disabled(model.busy)
    }

    private func languageLabel(_ title: String, caption: String) -> some View {
        VStack(spacing: 4) {
            Text(caption).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary).contentTransition(.opacity)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Image(systemName: "chevron.down").font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
            }
        }.frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: title)
    }

    private var modeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.settings.translationService == .api {
                Picker("模式", selection: translationMode) {
                    ForEach(store.settings.allowedModes) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("translationModePicker")
                    .accessibilityHint(store.settings.mode.detail)
            } else {
                HStack {
                    Text("快速翻译").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("系统翻译").font(.caption).foregroundStyle(.secondary)
                }.frame(minHeight: 32).accessibilityIdentifier("systemServiceSummary")
            }
            Text(modeDescription).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true)
        }.disabled(model.busy)
    }

    private var modeDescription: String {
        switch store.settings.mode {
        case .quick: return store.settings.quickEngine == .system ? "在本机翻译，首次使用需准备语言包" : "日常短句与消息，快速获取译文"
        case .professional: return "保留段落、列表与表格，支持逐段核对"
        case .visual: return "理解画面与图片文字 · 拍照确认后立即上传翻译"
        }
    }

    private var expandedInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(visualMode ? "图片" : "原文").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if !model.text.isEmpty {
                    Text("\(model.text.count) / 16000").font(.caption2.monospacedDigit())
                        .foregroundStyle(model.text.count > 16000 ? Color.orange : Color.secondary)
                }
                if hasContent {
                    Button { model.clear(); photo = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 18)).frame(width: 32, height: 32)
                            .frame(minWidth: 44, minHeight: 44)
                    }.foregroundStyle(.tertiary).buttonStyle(.plain).disabled(model.busy)
                        .accessibilityLabel("清空原文").accessibilityIdentifier("clearInputButton")
                }
            }.frame(minHeight: 32)
            if let preview = model.preview {
                Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 180)
                    .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("已选图片")
            }
            if visualMode && model.imageData == nil {
                VStack(spacing: 12) {
                    Image(systemName: "viewfinder").font(.largeTitle).foregroundStyle(.tertiary).accessibilityHidden(true)
                    Text("拍照、选择照片或粘贴图片开始翻译。").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: minimumEditorHeight, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            if !visualMode {
                Text(model.text.isEmpty ? " " : model.text + "\n")
                    .font(.system(size: inputFontSize)).lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8).padding(.horizontal, 5).hidden().accessibilityHidden(true)
                    .frame(minHeight: minimumEditorHeight, maxHeight: max(minimumEditorHeight, 260), alignment: .top)
                    .overlay(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            if model.text.isEmpty {
                                Text(model.imageData == nil ? "输入或粘贴文字…" : "识别图片或输入文字…")
                                    .font(.system(size: inputFontSize)).foregroundStyle(.tertiary)
                                    .padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                            }
                            TextEditor(text: $model.text).font(.system(size: inputFontSize)).lineSpacing(5)
                                .textInputAutocapitalization(.sentences).autocorrectionDisabled()
                                .scrollContentBackground(.hidden).focused($editing).disabled(model.busy)
                                .scrollDisabled(!editing)
                                .accessibilityLabel("原文").accessibilityIdentifier("sourceEditor")
                        }
                    }
            if let warning = model.ocrWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
            if model.imageData != nil {
                Picker("文字方向", selection: $model.textDirection) {
                    ForEach(OCRTextDirection.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).disabled(model.busy).accessibilityIdentifier("textDirectionPicker")
                Button(model.recognizedOCR?.reviewItems.isEmpty == false ? "复核 \(model.recognizedOCR?.reviewItems.count ?? 0) 处文字" : "核对识别文字") { editing = false; model.requestReview() }
                    .font(.subheadline).frame(minHeight: 44).disabled(model.busy).accessibilityIdentifier("recognizeOnly")
            }
            }
        }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
    }

    private var importActions: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
                PhotosPicker(selection: $photo, matching: .images) {
                    inputAction("照片", image: "photo")
                }.accessibilityLabel("选择照片").accessibilityIdentifier("choosePhoto")
                Button { openCamera() } label: { inputAction("拍照", image: "camera") }
                    .disabled(cameraStarting).accessibilityIdentifier("takePhoto")
                ClipboardPasteButton(imagesOnly: visualMode, tint: UIColor(theme.accent)) { providers in
                    editing = false; model.paste(providers)
                }.frame(maxWidth: .infinity, minHeight: 44)
            }.font(.body).tint(theme.accent).buttonStyle(.plain).disabled(model.busy)
    }

    private func inputAction(_ title: String, image: String) -> some View {
        Label(title, systemImage: image).foregroundStyle(theme.accent).frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.background, in: Capsule())
            .contentShape(Rectangle())
    }

    private var translationControls: some View {
        Group {
            if model.busy {
                TranslationProgressContent(model: model)
                if model.isTranslating {
                    Button("查看进度") { editing = false; showTranslationReader = true }
                        .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("resumeTranslation")
                }
            } else {
                Button {
                    if model.result != nil { editing = false; showTranslationReader = true }
                    else { startTranslation() }
                } label: {
                    HStack(spacing: 8) {
                        Text(model.result != nil ? "查看译文" : (visualMode ? "翻译图片" : (model.imageData != nil && model.text.isEmpty ? "识字并翻译" : "翻译")))
                        Image(systemName: model.result != nil ? "doc.text" : "arrow.right").accessibilityHidden(true)
                    }.font(.subheadline.weight(.semibold))
                        .foregroundStyle(hasInput && (!visualMode || model.imageData != nil) ? theme.onAccent : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 22)
                }.buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.roundedRectangle(radius: 16)).tint(theme.accent)
                    .disabled(!hasInput || (visualMode && model.imageData == nil)).accessibilityIdentifier("translateButton")
            }
        }
    }

    private func startTranslation() {
        editing = false
        model.translate()
        if model.busy || model.result != nil { showTranslationReader = true }
    }

    private func openCamera() {
        editing = false
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            model.error = "当前设备无法使用相机，请选择照片或粘贴图片。"; return
        }
        cameraStarting = true
        Task { @MainActor in
            let granted = await CameraAccess.request()
            cameraStarting = false
            if granted { cameraResult = nil; showCamera = true } else { cameraDenied = true }
        }
    }

    private func finishCamera() {
        guard let captured = cameraResult else { return }
        cameraResult = nil
        do { try model.acceptImage(captured.get()); startTranslation() }
        catch { model.error = error.localizedDescription }
    }

    private func updateLanguages(source: SourceLanguage, target: TargetLanguage) {
        do { try store.updateLanguages(source: source, target: target) } catch { model.error = error.localizedDescription }
    }
}

/// The system paste control keeps user-initiated clipboard access while allowing
/// the same neutral surface as the photo and camera tools.
private struct ClipboardPasteButton: UIViewRepresentable {
    let imagesOnly: Bool
    let tint: UIColor
    let receive: ([NSItemProvider]) -> Void

    func makeUIView(context: Context) -> PasteReceiverView { PasteReceiverView() }
    func updateUIView(_ view: PasteReceiverView, context: Context) {
        view.receive = receive
        view.configure(imagesOnly: imagesOnly, tint: tint)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PasteReceiverView, context: Context) -> CGSize? {
        let size = uiView.control?.sizeThatFits(CGSize(width: proposal.width ?? 120, height: .greatestFiniteMagnitude)) ?? .zero
        return CGSize(width: proposal.width ?? max(100, size.width), height: max(44, size.height))
    }
}

private final class PasteReceiverView: UIView {
    var receive: (([NSItemProvider]) -> Void)?
    private(set) var control: UIPasteControl?
    private var imagesOnly: Bool?
    private var foreground: UIColor?

    func configure(imagesOnly: Bool, tint: UIColor) {
        if self.imagesOnly != imagesOnly {
            self.imagesOnly = imagesOnly
            pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers:
                imagesOnly ? [UTType.image.identifier] : [UTType.image.identifier, UTType.text.identifier])
        }
        guard control == nil || foreground != tint else { return }
        foreground = tint
        control?.removeFromSuperview()
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconAndLabel
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .systemGroupedBackground
        configuration.baseForegroundColor = tint
        let control = UIPasteControl(configuration: configuration)
        control.target = self
        control.accessibilityIdentifier = "pasteInput"
        control.accessibilityLabel = "粘贴"
        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control); self.control = control
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor), control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.topAnchor.constraint(equalTo: topAnchor), control.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        invalidateIntrinsicContentSize()
    }

    override func paste(itemProviders: [NSItemProvider]) { receive?(itemProviders) }
}


private struct LiveTranslationReader: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var model: TranslationViewModel
    @ObservedObject var store: SettingsStore
    let editSource: () -> Void
    let review: (TranslationResult, Int) -> Void
    let retryVisual: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.busy {
                        TranslationProgressContent(model: model)
                            .padding(16).background(Theme.background, in: RoundedRectangle(cornerRadius: 18))
                        if model.result != nil {
                            Text("下方保留上次译文，完成后更新。").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let error = model.error {
                        if model.result == nil {
                            ContentUnavailableView {
                                Label("翻译未完成", systemImage: "text.bubble")
                            } description: {
                                Text(error)
                            } actions: {
                                retryButton
                            }.padding(.top, 24)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ErrorBanner(message: error)
                                retryButton
                            }
                        }
                    }
                    if let result = model.result {
                        ResultContent(result: result, store: store, compactHeading: true,
                            isWorking: model.busy,
                            onRetranslate: { model.translate(forceRefresh: true) }, onReviewBlock: { review(result, $0) },
                            sourceImageData: model.imageData)
                            .id("reader-start")
                    }
                    if model.imageData != nil, store.settings.mode != .visual, store.settings.translationService == .api,
                       model.result?.uncertainOCR == true || model.ocrWarning != nil || model.error == TranslationError.noText.localizedDescription {
                        Button("用识图模式重试", action: retryVisual).frame(minHeight: 44).accessibilityIdentifier("retryVisualMode")
                    }
                }.padding(.horizontal, 20).padding(.vertical, 16)
            }.accessibilityIdentifier("translationReaderScroll").background(Theme.canvas)
                .onChange(of: model.result?.id) { _, id in
                    if id != nil { DispatchQueue.main.async { proxy.scrollTo("reader-start", anchor: .top) } }
                }
        }.navigationTitle("译文").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑", action: editSource).accessibilityLabel("编辑原文").accessibilityIdentifier("editTranslationSource")
                }
            }
            .environment(\.appTheme, AppTheme(settings: store.settings))
    }

    private var retryButton: some View {
        Button { model.translate(forceRefresh: true) } label: {
            Label("重试翻译", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.semibold)).foregroundStyle(theme.onAccent)
                .frame(minHeight: 28)
        }.buttonStyle(.borderedProminent).controlSize(.large)
            .accessibilityIdentifier("retryTranslation")
    }
}

private struct TranslationProgressContent: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject var model: TranslationViewModel

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(alignment: .top, spacing: 12) {
                ProgressView().padding(.top, 4)
                TimelineView(.periodic(from: model.startedAt, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.phase.title).font(.subheadline.weight(.medium))
                        Text(waitingMessage(at: context.date)).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("translationProgress")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("取消") { model.cancel() }.buttonStyle(.bordered).controlSize(.regular)
                .frame(minHeight: 44).accessibilityIdentifier("cancelTranslation")
        }.padding(.vertical, 4)
    }

    private func waitingMessage(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(model.phaseStartedAt)))
        let message: String
        switch model.phase {
        case .recognizing: message = seconds > 5 ? "正在识字与局部复核" : "在本机识别文字"
        case .preparing: message = "正在准备图片"
        case .understanding, .translating: message = seconds > 10 ? "仍在等待结果，可随时取消" : "完成后在这里显示译文"
        default: message = "正在读取所选内容"
        }
        return "\(seconds) 秒 · \(message)"
    }
}
