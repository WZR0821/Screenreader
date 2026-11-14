import SwiftUI

@MainActor
final class TranslationBlockReviewModel: ObservableObject {
    let selection: TranslationReviewSelection
    @Published var drafts: [String]
    @Published private(set) var crop: Data?
    @Published private(set) var loadingCrop = false
    @Published private(set) var busy = false
    @Published private(set) var completed = false
    @Published var error: String?
    private let imageData: Data?
    private let pipeline: TranslationPipeline
    private var job: Task<Void, Never>?
    private var jobID = UUID()
    var isTable: Bool { selection.block?.tableCells != nil }
    var correctedText: String { drafts.joined(separator: isTable ? "\t" : "") }

    init(selection: TranslationReviewSelection, imageData: Data?, pipeline: TranslationPipeline = TranslationPipeline()) {
        self.selection = selection; self.imageData = imageData; self.pipeline = pipeline
        let text = selection.block?.original ?? ""
        drafts = selection.block?.tableCells != nil ? text.components(separatedBy: "\t") : [text]
    }

    func loadCrop() async {
        guard let imageData, let box = selection.block?.sourceBox else { return }
        loadingCrop = true
        let data = await Task.detached(priority: .userInitiated) { SourceImageCrop.png(imageData, box: box) }.value
        if !Task.isCancelled { crop = data }
        loadingCrop = false
    }

    func retranslate(using store: SettingsStore,
                     commit: @escaping @MainActor (TranslationResult, TranslationResult) throws -> Void) {
        guard !busy else { return }
        let snapshot: (AppSettings, String)
        let text = correctedText
        do {
            _ = try TranslationReview.sourceBlock(in: selection.result, blockID: selection.blockID, correctedText: text)
            snapshot = try store.credentials()
        } catch { self.error = error.localizedDescription; return }
        busy = true; error = nil
        jobID = UUID()
        let id = jobID
        job = Task {
            do {
                let block = try await pipeline.retranslateBlock(in: selection.result, blockID: selection.blockID,
                    correctedText: text, settings: snapshot.0, key: snapshot.1)
                let updated = try TranslationReview.replacing(in: selection.result, blockID: selection.blockID, with: block)
                try Task.checkCancellation()
                guard id == jobID else { return }
                try commit(selection.result, updated)
                completed = true
            } catch is CancellationError {} catch { if id == jobID { self.error = error.localizedDescription } }
            if id == jobID { busy = false; job = nil }
        }
    }

    func cancel() {
        job?.cancel(); job = nil; jobID = UUID(); busy = false
    }
}

struct TranslationBlockReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @ObservedObject var store: SettingsStore
    @StateObject private var model: TranslationBlockReviewModel
    @State private var showCrop = false
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0
    @FocusState private var editing: Int?
    let commit: @MainActor (TranslationResult, TranslationResult) throws -> Void
    private var allowsRetranslation: Bool { store.settings.translationService == .api }

    init(selection: TranslationReviewSelection, imageData: Data?, store: SettingsStore,
         pipeline: TranslationPipeline = TranslationPipeline(),
         commit: @escaping @MainActor (TranslationResult, TranslationResult) throws -> Void) {
        self.store = store; self.commit = commit
        _model = StateObject(wrappedValue: TranslationBlockReviewModel(selection: selection, imageData: imageData, pipeline: pipeline))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(!allowsRetranslation ? "对照原图和原文查看完整译文。需要修改时，可返回编辑原文后重新翻译。" : (model.isTable ? "逐列核对原文与译文。修改后只重译这一行，其他译文保留。"
                                       : "对照原图和原文核对译文。修改后只重译这一段，其他译文保留。"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    if let data = model.crop, let image = UIImage(data: data) {
                        Button { editing = nil; showCrop = true } label: {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 280)
                        }.buttonStyle(.plain).disabled(model.busy)
                            .accessibilityLabel("放大本段原图区域").accessibilityIdentifier("translationReviewCrop")
                        Text("点按放大，可双指缩放。").font(.caption).foregroundStyle(.secondary)
                    } else if model.loadingCrop { ProgressView("正在读取原图区域") }
                    else { Text("此处没有可用的原图区域，可直接核对下方原文。翻译记录不保存原图。")
                        .font(.caption).foregroundStyle(.secondary) }
                } header: { Text("原图区域").sectionTitle() }
                if model.isTable {
                    ForEach(model.drafts.indices, id: \.self) { column in
                        Section {
                            sourceEditor(column)
                            Text("当前译文").font(.caption).foregroundStyle(.secondary)
                            translatedText(model.selection.block?.tableCells?[column] ?? "")
                                .accessibilityIdentifier("reviewCurrentCell-\(column)")
                        } header: { Text("第 \(column + 1) 列").sectionTitle() }
                    }
                } else {
                    Section { sourceEditor(0) } header: {
                        Text(allowsRetranslation ? "原文（可修正）" : "原文").sectionTitle()
                    }
                    Section {
                        translatedText(model.selection.block?.text ?? "")
                            .accessibilityIdentifier("reviewCurrentTranslation")
                    } header: { Text("当前译文 · \(model.selection.result.target)").sectionTitle() }
                }
                if let engine = model.selection.block?.reviewEngine {
                    Section {
                        Text("本段上次重译：\(engine)\(model.selection.block?.reviewSeconds.map { String(format: " · %.2f 秒", $0) } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = model.error { Section { ErrorBanner(message: error) } }
                if allowsRetranslation { Section {
                    Text("重译使用 \(store.settings.engineLabel)，目标语言为\(model.selection.result.target)。仅发送本段原文。")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("reviewRequestScope")
                    if model.correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("请填写原文后再重译。表格中的单个单元格可以留空。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } }
            }.groupedListSpacing().navigationTitle("核对译文").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    if allowsRetranslation {
                    VStack(spacing: 10) {
                        if model.busy {
                            HStack(spacing: 10) { ProgressView(); Text(model.isTable ? "正在重译这一行" : "正在重译这一段") }
                                .font(.subheadline)
                            Button("取消重译", role: .cancel) { model.cancel() }
                                .frame(minHeight: 44).accessibilityIdentifier("cancelBlockRetranslation")
                        } else {
                            Button {
                                editing = nil; model.retranslate(using: store, commit: commit)
                            } label: {
                                Text(model.isTable ? "仅重译这一行" : "仅重译这一段")
                                    .font(.body.weight(.semibold)).foregroundStyle(theme.onAccent)
                                    .frame(maxWidth: .infinity, minHeight: 28)
                            }.buttonStyle(.borderedProminent).controlSize(.large)
                                .buttonBorderShape(.roundedRectangle(radius: 16))
                                .disabled(model.correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("retranslateBlock")
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: .infinity).background(.bar)
                    }
                }
                .toolbar {
                    if JapaneseFurigana.isJapanese(target: model.selection.result.target) {
                        ToolbarItem(placement: .topBarTrailing) { FuriganaToggleButton(store: store) }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button(model.busy ? "取消" : "完成") { model.cancel(); dismiss() }
                            .accessibilityIdentifier("closeTranslationReview")
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer(); Button("完成") { editing = nil }.accessibilityIdentifier("finishReviewEditing")
                    }
                }
                .task { await model.loadCrop() }
                .onChange(of: model.completed) { _, done in if done { dismiss() } }
                .onDisappear { model.cancel() }
                .sheet(isPresented: $showCrop) {
                    if let data = model.crop, let image = UIImage(data: data) { TranslationSourceCropView(image: image).readerSheet() }
                }
        }.interactiveDismissDisabled(model.busy)
    }

    private func translatedText(_ text: String) -> some View {
        JapaneseTranslationText(text: text, target: model.selection.result.target, reader: store.settings.reader, textScale: textScale)
    }

    private func sourceEditor(_ column: Int) -> some View {
        Group {
        if !allowsRetranslation {
            Text(model.drafts[column]).textSelection(.enabled).accessibilityIdentifier("translationReviewSource-\(column)")
        } else {
        HStack(alignment: .top, spacing: 8) {
        TextField(model.isTable ? "本列原文（可以留空）" : "本段原文", text: Binding(
            get: { model.drafts[column] }, set: { model.drafts[column] = $0; model.error = nil }), axis: .vertical)
            .lineLimit(2...14).textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($editing, equals: column).disabled(model.busy)
            .accessibilityLabel(model.isTable ? "第\(column + 1)列原文" : "本段原文")
            .accessibilityIdentifier("translationReviewSource-\(column)")
        if !model.drafts[column].isEmpty {
            Button {
                editing = nil; model.drafts[column] = ""; model.error = nil
            } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                .buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.busy)
                .accessibilityLabel(model.isTable ? "清空第\(column + 1)列原文" : "清空本段原文")
                .accessibilityIdentifier("clearReviewSource-\(column)")
        }
        }
        }
        }
    }
}

private struct TranslationSourceCropView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    @State private var scale = 1.0
    @State private var baseScale = 1.0
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image).resizable().scaledToFit().frame(width: geometry.size.width * scale)
                        .gesture(MagnifyGesture().onChanged { scale = min(6, max(1, baseScale * $0.magnification)) }
                            .onEnded { _ in baseScale = scale })
                        .onTapGesture(count: 2) { scale = scale > 1 ? 1 : 3; baseScale = scale }
                        .accessibilityLabel("本段原图，支持双指缩放和双击放大")
                }
            }.navigationTitle("原图区域").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
