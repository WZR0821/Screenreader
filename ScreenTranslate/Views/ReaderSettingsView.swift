import SwiftUI

struct ReaderSettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var error: String?
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0

    var body: some View {
        Form {
            Section("字号") {
                Picker("字号", selection: Binding(get: { store.settings.reader.textSize }, set: { value in update { $0.textSize = value } })) {
                    ForEach(ReaderTextSize.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("readerTextSizePicker")
            }
            Section {
                Picker("间距", selection: Binding(get: { store.settings.reader.spacing }, set: { value in update { $0.spacing = value } })) {
                    ForEach(ReaderSpacing.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("readerSpacingPicker")
                Toggle("默认展开原文", isOn: Binding(get: { store.settings.reader.showOriginal }, set: { value in update { $0.showOriginal = value } }))
                    .accessibilityIdentifier("readerOriginalToggle")
            } header: { Text("阅读间距") } footer: {
                Text("即选即保存，应用于 App、记录及下次全文窗口。窗口内可点“查看原文”展开或收起；其余提示留在 App 内。颜色跟随外观设置。系统窗口高度与工具栏由 iOS 决定。")
            }
            Section("阅读预览") {
                VStack(alignment: .leading, spacing: store.settings.reader.spacing.paragraph) {
                    Text("Double cheeseburger set").fontWeight(.semibold)
                    Text("The sauce contains pickles, mayonnaise, ketchup and mustard.\nRemoving any one of these means the burger comes without sauce.")
                    Text("Price  ¥1,100\nQuantity  1")
                    if store.settings.reader.showOriginal {
                        Divider()
                        Text("原文\nCheese Burger (Double) Set").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: store.settings.reader.textSize.points * textScale))
                .lineSpacing(store.settings.reader.spacing.line)
                .fixedSize(horizontal: false, vertical: true).padding(.vertical, 10)
                .accessibilityIdentifier("readerPreview")
            }
            if let error { Section { ErrorBanner(message: error) } }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("译文显示").navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ change: (inout ReaderPreferences) -> Void) {
        var settings = store.settings
        change(&settings.reader)
        do { try store.save(settings, keys: [:]); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
