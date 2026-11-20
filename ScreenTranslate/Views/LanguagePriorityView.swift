import SwiftUI

/// 设置 → 翻译偏好 → 语言优先级. Text that is already in the target language
/// goes to the first other language in this order.
struct LanguagePriorityView: View {
    @ObservedObject var store: SettingsStore
    @State private var error: String?

    private var order: [TargetLanguage] { AppSettings.normalizedPriority(store.settings.languagePriority) }

    var body: some View {
        List {
            if let error { Section { ErrorBanner(message: error) } }
            Section {
                Toggle("自动改译", isOn: Binding(get: { store.settings.smartTarget },
                                              set: { value in change { $0.smartTarget = value } }))
                    .accessibilityIdentifier("smartTargetToggle")
            } footer: {
                Text("原文语言选“自动识别”时生效。输入的内容已经是目标语言，就改译成下面顺序里排在最前的另一种语言。")
            }
            if store.settings.smartTarget {
                Section {
                    ForEach(Array(order.enumerated()), id: \.element) { index, language in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            Text(language.title)
                        }.accessibilityElement(children: .combine)
                            .accessibilityLabel("第 \(index + 1) 位：\(language.title)")
                            .accessibilityIdentifier("languagePriorityRow-\(index + 1)")
                            .accessibilityValue(language.title)
                    }.onMove { offsets, destination in
                        var moved = order
                        moved.move(fromOffsets: offsets, toOffset: destination)
                        change { $0.languagePriority = moved }
                    }
                } header: { Text("优先顺序").sectionTitle() } footer: {
                    Text("按住右侧的三条横线拖动排序。全是汉字、分不出是中文还是日语的输入，按排在前面的那种处理。")
                }
                Section {
                    ForEach(order) { language in
                        LabeledContent("原文和目标都是\(language.title)",
                                       value: "译为\(store.settings.fallbackTarget(for: language).title)")
                            .accessibilityIdentifier("languagePriorityEffect-\(language.languageCode)")
                    }
                } header: { Text("当前效果").sectionTitle() } footer: {
                    Text("手动指定了原文语言、用识图模式，或者内容是中日英混排、繁体中文时，仍按所选目标语言翻译。截图和照片要整张都是目标语言才改译，里面有别的语言的句子就照常翻译。")
                }
            }
        }
        // The order is always editable, like the language list in iPhone Settings.
        .environment(\.editMode, .constant(.active))
        .settingsList().navigationTitle("语言优先级").navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: store.settings.smartTarget)
    }

    private func change(_ edit: (inout AppSettings) -> Void) {
        do { try store.change(edit); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
