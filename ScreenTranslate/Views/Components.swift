import SwiftUI

enum Theme {
    static let canvas = Color(uiColor: .systemBackground)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

extension UIColor {
    convenience init(rgb: ThemeRGB) {
        let value = rgb.normalized
        self.init(red: value.red, green: value.green, blue: value.blue, alpha: 1)
    }
}

struct AppTheme {
    var settings = AppSettings()
    private func color(dark: Bool) -> ThemeRGB {
        let source = settings.accentTheme == .custom ? settings.customAccent : settings.accentTheme.color
        return source.accessible(on: .hex(dark ? 0x2C2C2E : 0xF2F2F7))
    }
    var accent: Color { Color(uiColor: UIColor { UIColor(rgb: color(dark: $0.userInterfaceStyle == .dark)) }) }
    var onAccent: Color { Color(uiColor: UIColor { UIColor(rgb: color(dark: $0.userInterfaceStyle == .dark).foreground) }) }
    var colorScheme: ColorScheme? {
        switch settings.appearance { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

private struct AppThemeKey: EnvironmentKey { static let defaultValue = AppTheme() }
extension EnvironmentValues {
    var appTheme: AppTheme { get { self[AppThemeKey.self] } set { self[AppThemeKey.self] = newValue } }
}

extension View {
    func readerSheet() -> some View {
        presentationDetents([.large]).presentationDragIndicator(.visible)
            .presentationCornerRadius(28).presentationBackground(Theme.background)
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.035), lineWidth: 1))
    }
}

struct ErrorBanner: View {
    var message: String
    var body: some View {
        Label { Text(message).font(.subheadline) } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .foregroundStyle(.red)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("errorBanner")
    }
}

struct ResultContent: View {
    @Environment(\.appTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0
    @State private var originalExpanded = false
    @State private var showInformation = false
    @State private var copied = false
    @State private var copyCount = 0
    @State private var showsImageTranslation = true
    var result: TranslationResult
    var store: SettingsStore? = nil
    var compactHeading = false
    var isWorking = false
    var onRetranslate: (() -> Void)? = nil
    var onReviewBlock: ((Int) -> Void)? = nil
    var sourceImageData: Data? = nil
    private var hasImageTranslation: Bool { sourceImageData != nil && !ImageTranslationLayout.items(in: result).isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 2) {
                Text(compactHeading ? result.target : "译文").font(.subheadline.weight(.semibold))
                if !compactHeading { Text(result.target).font(.caption).foregroundStyle(.secondary).padding(.leading, 6) }
                Spacer(minLength: 4)
                if JapaneseFurigana.isJapanese(target: result.target), let store {
                    FuriganaToggleButton(store: store)
                }
                Button {
                    UIPasteboard.general.string = result.translated; copied = true; copyCount += 1
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 16)).frame(width: 44, height: 44)
                }.foregroundStyle(copied ? theme.accent : Color.secondary)
                    .accessibilityLabel("复制译文").accessibilityValue(copied ? "已复制" : "")
                    .accessibilityIdentifier("copyTranslation").sensoryFeedback(.success, trigger: copyCount)
                Menu {
                    ShareLink(item: result.translated) { Label("分享译文", systemImage: "square.and.arrow.up") }
                    Button { showInformation = true } label: { Label("翻译信息", systemImage: "info.circle") }
                        .accessibilityIdentifier("showTranslationInformation")
                    if let onRetranslate {
                        Button(action: onRetranslate) { Label("重新翻译", systemImage: "arrow.clockwise") }
                            .disabled(isWorking)
                            .accessibilityIdentifier("retranslateResult")
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16)).frame(width: 44, height: 44)
                }.foregroundStyle(.secondary).accessibilityLabel("更多译文操作").accessibilityIdentifier("translationActions")
            }.buttonStyle(.plain).tint(.secondary)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("translationResultHeader")
            if let warning = result.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if hasImageTranslation {
                Picker("译文显示方式", selection: $showsImageTranslation) {
                    Text("原图直译").tag(true)
                    Text("阅读").tag(false)
                }.pickerStyle(.segmented).accessibilityIdentifier("translationPresentationPicker")
            }
            if hasImageTranslation, showsImageTranslation, let sourceImageData {
                ImageTranslationView(data: sourceImageData, result: result, isWorking: isWorking) { onReviewBlock?($0) }
            } else {
            VStack(alignment: .leading, spacing: theme.settings.reader.paragraphSpacing) {
                ForEach(Array(readingGroups.enumerated()), id: \.offset) { groupIndex, group in
                    let index = readingGroups.prefix(groupIndex).reduce(0) { $0 + $1.count }
                    let block = group[0]
                    if block.tableCells != nil {
                        TranslationTableView(blocks: group, firstIndex: index,
                            reader: theme.settings.reader, textScale: textScale, target: result.target, onReviewBlock: onReviewBlock, isWorking: isWorking,
                            reviewableIDs: Set(group.filter { TranslationReview.canReview(result, blockID: $0.id) }.map(\.id)))
                    } else {
                    HStack(alignment: .top, spacing: 10) {
                    Group {
                        if let field = block.fieldParts {
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                translatedText(field.label, block: block)
                                Spacer(minLength: 0)
                                translatedText(field.value, block: block, alignment: .right)
                            }.accessibilityElement(children: .combine)
                                .accessibilityLabel(block.text)
                                .accessibilityIdentifier(index == 0 ? "translationResult" : "translationParagraph-\(index)")
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                if block.kind == .listItem && !block.hasVisibleListMarker { Text("•").foregroundStyle(.secondary) }
                                translatedText(block.kind == .listItem ? block.listText : block.text, block: block)
                                    .accessibilityAddTraits(block.kind == .heading ? .isHeader : [])
                                    .accessibilityIdentifier(index == 0 ? "translationResult" : "translationParagraph-\(index)")
                            }
                        }
                    }.font(theme.settings.reader.displayFont(scale: textScale, heading: block.kind == .heading))
                        .lineSpacing(theme.settings.reader.lineSpacing * textScale).textSelection(.enabled)
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    if let onReviewBlock, TranslationReview.canReview(result, blockID: block.id) {
                        TranslationReviewButton(block: block) { onReviewBlock(block.id) }
                            .disabled(isWorking)
                    }
                    }
                    }
                }
            }
            if !result.original.isEmpty && ((result.mode != .visual && result.imageMode != .visual) || result.visualOCR == true) {
              DisclosureGroup("查看原文", isExpanded: $originalExpanded) {
                Text(result.original).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                if let raw = result.rawOCR {
                    DisclosureGroup("完整识别文字（含已过滤项）") {
                        Text(raw).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }.padding(.top, 8)
                }
              }.font(.caption).foregroundStyle(.secondary).padding(.top, 2)
            }
            }
            if hasReviews {
                Text("已局部重译 · \((result.blocks ?? []).filter { $0.reviewEngine != nil }.count) 段")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("translationReviewSummary")
            }
        }
        .onAppear { originalExpanded = theme.settings.reader.showOriginal }
        .onChange(of: theme.settings.reader.showOriginal) { _, value in originalExpanded = value }
        .onChange(of: result.id) { _, _ in originalExpanded = theme.settings.reader.showOriginal; copied = false; showsImageTranslation = true }
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copied = false
        }
        .sheet(isPresented: $showInformation) {
            TranslationInformationView(result: result)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                .presentationCornerRadius(28).presentationBackground(Theme.background)
        }
    }

    private func translatedText(_ text: String, block: ReadingBlock, alignment: NSTextAlignment = .natural) -> some View {
        JapaneseTranslationText(text: text, target: result.target, reader: theme.settings.reader,
            textScale: textScale, heading: block.kind == .heading, medium: alignment == .right, alignment: alignment)
    }
    private var hasReviews: Bool { result.blocks?.contains { $0.reviewEngine != nil } == true }
    private var readingGroups: [[ReadingBlock]] {
        var groups: [[ReadingBlock]] = []
        for block in result.blocks ?? ReadingBlock.plainText(result.translated) {
            if block.kind == .tableRow, groups.last?.last?.tableCells != nil { groups[groups.count - 1].append(block) }
            else { groups.append([block]) }
        }
        return groups
    }

}

private struct TranslationInformationView: View {
    @Environment(\.dismiss) private var dismiss
    let result: TranslationResult
    private var hasReviews: Bool { result.blocks?.contains { $0.reviewEngine != nil } == true }
    var body: some View {
        NavigationStack {
            Form {
                Section("翻译") {
                    LabeledContent("目标语言", value: result.target)
                    LabeledContent("模式", value: result.mode?.title ?? "翻译")
                    LabeledContent(hasReviews ? "初次翻译引擎" : "引擎", value: result.engine)
                    if result.usedCache == true { Label("复用译文", systemImage: "checkmark.circle") }
                }
                Section(hasReviews ? "初次翻译耗时" : "耗时") {
                    if let seconds = result.preparationSeconds { LabeledContent("图片／语言准备", value: duration(seconds)) }
                    if let seconds = result.recognitionSeconds {
                        LabeledContent("本机识字", value: duration(max(0, seconds - (result.refinementSeconds ?? 0))))
                    }
                    if let seconds = result.refinementSeconds { LabeledContent("局部复核", value: duration(seconds)) }
                    if let seconds = result.requestSeconds { LabeledContent(result.usedCache == true ? "读取缓存" : "翻译", value: duration(seconds)) }
                    LabeledContent("本次总计", value: duration(result.elapsed))
                }.accessibilityIdentifier("translationTimings")
                if let warning = result.warning { Section("提示") { Text(warning).font(.subheadline) } }
            }.navigationTitle("翻译信息").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
    private func duration(_ seconds: TimeInterval) -> String { String(format: "%.2f 秒", seconds) }
}

struct TranslationReviewButton: View {
    let block: ReadingBlock
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(block.reviewEngine == nil ? "核对" : "已核对", systemImage: block.reviewEngine == nil ? "text.magnifyingglass" : "checkmark.circle")
                .font(.caption).frame(minHeight: 44)
        }.buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("核对第\(block.id)\(block.tableCells == nil ? "段" : "行")译文")
            .accessibilityIdentifier("reviewTranslationBlock-\(block.id)")
    }
}

struct RecentResultView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var query = ""
    @State private var confirmClear = false
    private var filtered: [TranslationResult] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.history.filter { term.isEmpty || $0.translated.localizedCaseInsensitiveContains(term) || $0.original.localizedCaseInsensitiveContains(term) }
    }
    private var days: [Date] {
        Array(Set(filtered.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >)
    }
    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorBanner(message: error) }
                ForEach(days, id: \.self) { day in
                    Section(day.formatted(.dateTime.month().day())) {
                        ForEach(filtered.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { result in
                            NavigationLink {
                                RecentResultDetailView(store: store, resultID: result.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(result.translated).font(.body).lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text("\(result.mode?.title ?? "翻译") · \(result.target)")
                                        Spacer()
                                        Text(result.date, style: .time)
                                    }.font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 7)
                            }.accessibilityIdentifier("historyRow-\(result.id.uuidString)")
                                .swipeActions {
                                    Button("删除", role: .destructive) {
                                        do { try store.deleteResult(result.id) } catch { self.error = error.localizedDescription }
                                    }
                                }
                        }
                    }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "还没有翻译记录" : "没有匹配的记录", systemImage: query.isEmpty ? "clock" : "magnifyingglass",
                        description: Text(query.isEmpty ? "完成翻译后自动保存，最多保留 \(store.settings.historyLimit) 条。" : "试试其他原文或译文关键词。"))
                }
            }
            .searchable(text: $query, prompt: "搜索原文或译文")
            .scrollContentBackground(.hidden).background(Theme.background).navigationTitle("翻译记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空", role: .destructive) { confirmClear = true }.disabled(store.history.isEmpty)
                        .tint(.red)
                }
            }
            .confirmationDialog("清空全部翻译记录？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空记录", role: .destructive) {
                    do { try store.clearRecent() } catch { self.error = error.localizedDescription }
                }
            } message: { Text("清空后无法恢复。") }
        }
    }
}

struct RecentResultDetailView: View {
    @ObservedObject var store: SettingsStore
    let resultID: UUID
    @State private var review: TranslationReviewSelection?
    private var result: TranslationResult? { store.history.first { $0.id == resultID } }
    var body: some View {
        ScrollView {
            if let result {
                ResultContent(result: result, store: store, compactHeading: true,
                    onReviewBlock: { review = .init(result: result, blockID: $0) })
                    .padding(.horizontal, 20).padding(.vertical, 16)
            } else {
                ContentUnavailableView("这条记录已删除", systemImage: "clock")
            }
        }.accessibilityIdentifier("recentResultScroll")
            .background(Theme.canvas).navigationTitle("译文").navigationBarTitleDisplayMode(.inline)
            .environment(\.appTheme, AppTheme(settings: store.settings))
            .sheet(item: $review) { selection in
                TranslationBlockReviewView(selection: selection, imageData: nil, store: store) { expected, updated in
                    guard try store.replaceRecordedResult(expected, with: updated) else { throw TranslationError.reviewConflict }
                }.readerSheet()
            }
    }
}
