import SwiftUI

enum Theme {
    static let canvas = dynamic(light: 0xFAF9F7, dark: 0x171715)
    static let background = dynamic(light: 0xF1F0EC, dark: 0x171715)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(uiColor: UIColor { UIColor(rgb: .hex($0.userInterfaceStyle == .dark ? dark : light)) })
    }
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
        return source.accessible(on: .hex(dark ? 0x2C2C2E : 0xF1F0EC))
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
    var result: TranslationResult
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(result.mode?.title ?? (result.imageMode == .visual ? "识图" : "翻译")) · \(result.target)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button { UIPasteboard.general.string = result.translated } label: {
                    Image(systemName: "doc.on.doc").frame(width: 44, height: 44)
                }.accessibilityLabel("复制译文").accessibilityIdentifier("copyTranslation")
                ShareLink(item: result.translated) { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }
                    .accessibilityLabel("分享译文")
            }.foregroundStyle(.secondary).buttonStyle(.plain)
            if let warning = result.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: theme.settings.reader.spacing.paragraph) {
                ForEach(Array((result.blocks ?? ReadingBlock.plainText(result.translated)).enumerated()), id: \.offset) { index, block in
                    Group {
                        if let cells = block.tableCells {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                ForEach(Array(cells.enumerated()), id: \.offset) { cellIndex, value in
                                    Text(value).fontWeight(block.kind == .tableHeader ? .semibold : .regular)
                                        .frame(maxWidth: .infinity, alignment: cellIndex == cells.count - 1 ? .trailing : .leading)
                                        .multilineTextAlignment(cellIndex == cells.count - 1 ? .trailing : .leading)
                                }
                            }.padding(.vertical, 5).accessibilityElement(children: .combine)
                                .accessibilityLabel(cells.joined(separator: "，"))
                                .accessibilityIdentifier(index == 0 ? "translationResult" : "translationParagraph-\(index)")
                        } else if let field = block.fieldParts {
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                Text(field.label)
                                Spacer(minLength: 0)
                                Text(field.value).fontWeight(.medium).multilineTextAlignment(.trailing)
                            }.accessibilityElement(children: .combine)
                                .accessibilityLabel(block.text)
                                .accessibilityIdentifier(index == 0 ? "translationResult" : "translationParagraph-\(index)")
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                if block.kind == .listItem && !block.hasVisibleListMarker { Text("•").foregroundStyle(.secondary) }
                                Text(block.kind == .listItem ? block.listText : block.text)
                                    .accessibilityAddTraits(block.kind == .heading ? .isHeader : [])
                                    .accessibilityIdentifier(index == 0 ? "translationResult" : "translationParagraph-\(index)")
                            }
                        }
                    }.font(.system(size: (theme.settings.reader.textSize.points + (block.kind == .heading ? 3 : 0)) * textScale,
                        weight: block.kind == .heading ? .semibold : .regular))
                        .lineSpacing(theme.settings.reader.spacing.line).textSelection(.enabled)
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
              }
            }
            HStack {
                Text(result.engine).lineLimit(1)
                if result.usedCache == true { Text("复用译文") }
                Text(String(format: "%.1f s", result.elapsed))

            }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .onAppear { originalExpanded = theme.settings.reader.showOriginal }
        .onChange(of: theme.settings.reader.showOriginal) { _, value in originalExpanded = value }
        .onChange(of: result.id) { _, _ in originalExpanded = theme.settings.reader.showOriginal }
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
                                ScrollView { ResultContent(result: result).padding(24) }
                                    .accessibilityIdentifier("recentResultScroll")
                                    .background(Theme.canvas).navigationTitle("翻译").navigationBarTitleDisplayMode(.inline)
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
            .toolbarBackground(Theme.canvas, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) { confirmClear = true }.disabled(store.history.isEmpty)
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
