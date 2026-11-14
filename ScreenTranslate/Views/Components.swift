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

    /// The look every settings list shares: taller rows than the system default,
    /// and less empty space above the first group and between groups.
    /// - Parameter icons: every row carries an icon, so rows get a little more height.
    func settingsList(icons: Bool = false) -> some View {
        modifier(SettingsListStyle(icons: icons))
    }

    /// Only the spacing of `settingsList()`, for lists whose rows hold longer
    /// text or images and so set their own height.
    func groupedListSpacing() -> some View {
        listSectionSpacing(ListMetrics.sectionSpacing)
            .environment(\.defaultMinListHeaderHeight, 0)
            // Setting the margin replaces the system's own space above the first group.
            .contentMargins(.top, ListMetrics.topMargin, for: .scrollContent)
    }

    /// A group title in a grouped list: the system look, without forced capitals
    /// and with less empty space above it. `listSectionSpacing` alone leaves the
    /// title's own padding in place, which is most of the gap between two groups.
    func sectionTitle() -> some View {
        textCase(nil).listRowInsets(EdgeInsets(top: ListMetrics.titleTop, leading: 20,
                                               bottom: ListMetrics.titleBottom, trailing: 20))
    }
}

/// Spacing of the settings lists. Measured on screen, two groups with a title
/// between them end up `sectionSpacing + titleTop + titleBottom + 15.7` points
/// apart, and two groups without one exactly `sectionSpacing`.
enum ListMetrics {
    /// Between two groups; a group's title adds its own height to this.
    static let sectionSpacing: CGFloat = 20
    /// Above the first group under an inline navigation bar.
    static let topMargin: CGFloat = 12
    static let titleTop: CGFloat = 2
    static let titleBottom: CGFloat = 6
    /// The least height of a row of text, and of a row that carries an icon.
    static let rowHeight: CGFloat = 52
    static let iconRowHeight: CGFloat = 60
    /// Above and below a label of two lines, which makes its row a little taller than a one-line row.
    static let twoLinePadding: CGFloat = 2
}

private struct SettingsListStyle: ViewModifier {
    @ScaledMetric private var rowHeight: CGFloat

    init(icons: Bool) {
        _rowHeight = ScaledMetric(wrappedValue: icons ? ListMetrics.iconRowHeight : ListMetrics.rowHeight,
                                  relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden).background(Theme.background)
            .environment(\.defaultMinListRowHeight, rowHeight)
            .groupedListSpacing()
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ErrorBanner: View {
    var message: String
    var body: some View {
        // Red marks the state; the message itself stays in the primary colour so
        // a long provider message remains easy to read.
        Label {
            Text(message).font(.subheadline).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    /// 原图直译 is an optional module: without it the result is text only.
    private var hasImageTranslation: Bool {
        theme.settings.imageOverlay && sourceImageData != nil && !ImageTranslationLayout.items(in: result).isEmpty
    }
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
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 17)).frame(width: 44, height: 44)
                        .contentTransition(.symbolEffect(.replace))
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
                    Image(systemName: "ellipsis.circle").font(.system(size: 17)).frame(width: 44, height: 44)
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
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
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
                        // The 44-point target reaches past the line, so a short
                        // block stays as tall as its text.
                        TranslationReviewButton(block: block) { onReviewBlock(block.id) }
                            .disabled(isWorking).padding(.vertical, -10)
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
                Section {
                    LabeledContent("目标语言", value: result.target)
                    LabeledContent("模式", value: result.mode?.title ?? "翻译")
                    LabeledContent(hasReviews ? "初次翻译引擎" : "引擎", value: result.engine)
                    if result.usedCache == true { Label("复用译文", systemImage: "checkmark.circle") }
                } header: { Text("翻译").sectionTitle() }
                Section {
                    if let seconds = result.preparationSeconds { LabeledContent("图片／语言准备", value: duration(seconds)) }
                    if let seconds = result.recognitionSeconds {
                        LabeledContent("本机识字", value: duration(max(0, seconds - (result.refinementSeconds ?? 0))))
                    }
                    if let seconds = result.refinementSeconds { LabeledContent("局部复核", value: duration(seconds)) }
                    if let seconds = result.requestSeconds { LabeledContent(result.usedCache == true ? "读取缓存" : "翻译", value: duration(seconds)) }
                    LabeledContent("本次总计", value: duration(result.elapsed))
                } header: { Text(hasReviews ? "初次翻译耗时" : "耗时").sectionTitle() }
                .accessibilityIdentifier("translationTimings")
                if let warning = result.warning {
                    Section { Text(warning).font(.subheadline) } header: { Text("提示").sectionTitle() }
                }
            }.settingsList().navigationTitle("翻译信息").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
    private func duration(_ seconds: TimeInterval) -> String { String(format: "%.2f 秒", seconds) }
}

/// A quiet icon beside each block. It sits on the block's first text line, so a
/// page of short blocks no longer reads as a column of buttons.
struct TranslationReviewButton: View {
    @Environment(\.appTheme) private var theme
    let block: ReadingBlock
    let action: () -> Void
    private var reviewed: Bool { block.reviewEngine != nil }
    var body: some View {
        Button(action: action) {
            Text(Image(systemName: reviewed ? "checkmark.circle.fill" : "text.magnifyingglass"))
                .font(.callout)
                .foregroundStyle(reviewed ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.tertiary))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityValue(reviewed ? "已核对" : "")
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
                    Section {
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
                    } header: { Text(day.formatted(.dateTime.month().day())).sectionTitle() }
                }
            }
            .groupedListSpacing()
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

/// Pages that keep a draft hide the back button while it differs from what is
/// saved, so leaving never drops changes silently.
struct UnsavedChangesGuard: ViewModifier {
    let hasChanges: Bool
    let save: () -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var asking = false

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(hasChanges)
            .toolbar {
                if hasChanges {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { asking = true }.accessibilityIdentifier("discardChangesButton")
                    }
                }
            }
            .confirmationDialog("有尚未保存的更改", isPresented: $asking, titleVisibility: .visible) {
                Button("保存") { if save() { dismiss() } }
                Button("放弃更改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
    }
}
