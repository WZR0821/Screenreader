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
                    Text("截图、照片、识图和操作按钮按画面的主要内容判断，界面上的短标签、人名和链接不算；主要内容是\(order[0].title)时，要整张都是\(order[0].title)才改译，以免漏译夹在里面的外语。手动指定了原文语言、几种语言分量相当或是繁体中文时，仍按所选目标语言翻译。")
                        .accessibilityIdentifier("languagePriorityScreenNote")
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
