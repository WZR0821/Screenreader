import SwiftUI

struct PromptSettingsView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var store: SettingsStore
    @State private var selectedMode: TranslationMode = .quick
    @State private var drafts: [String: String] = [:]
    @State private var loaded = false
    @State private var notice: String?
    @State private var error: String?
    @FocusState private var editing: Bool

    private var prompt: Binding<String> {
        Binding(get: { drafts[selectedMode.rawValue] ?? "" }, set: {
            drafts[selectedMode.rawValue] = $0; notice = nil
        })
    }
    private var preview: String {
        var settings = store.settings
        settings.mode = selectedMode; settings.customPrompt = prompt.wrappedValue
        return (try? (selectedMode == .visual ? TextPreparation.imageInstructions(settings: settings)
            : TextPreparation.instructions(settings: settings))) ?? "请缩短自定义提示词后再预览。"
    }
    var body: some View {
        Form {
            Section {
                Picker("模式", selection: $selectedMode) {
                    ForEach(TranslationMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("promptModePicker")
                Text("每种 API 模式都有独立的默认要求和自定义提示词。系统翻译不使用提示词。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                ZStack(alignment: .topLeading) {
                    if prompt.wrappedValue.isEmpty {
                        Text("填写\(selectedMode.title)模式的翻译要求…")
                            .foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: prompt).frame(minHeight: 180).focused($editing)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("customPromptEditor")
                }
                HStack {
                    Text("\(prompt.wrappedValue.count) / 8000").font(.caption.monospacedDigit())
                        .foregroundStyle(prompt.wrappedValue.count > 8000 ? .red : .secondary)
                    Spacer()
                    Button("示例") { prompt.wrappedValue = TextPreparation.promptExample(for: selectedMode) }
                        .font(.caption).frame(minHeight: 44).accessibilityIdentifier("insertPromptExampleButton")
                    Button("恢复默认") { prompt.wrappedValue = "" }
                        .font(.caption).frame(minHeight: 44).accessibilityIdentifier("resetPromptButton")
                }
            } header: { Text("\(selectedMode.title)模式要求") } footer: {
                Text("留空即使用该模式的默认要求。可调整措辞与术语，事实、目标语言和模式结构仍会保留。保存会将三种模式的草稿同步用于 App 和操作按钮。")
            }
            Section {
                DisclosureGroup("可用变量") {
                    token("{source_language}", "原文语言")
                    token("{target_language}", "目标语言")
                    token("{tone}", "表达风格")
                    token("{glossary}", "术语表")
                }
                DisclosureGroup("预览模型指令（英文）") {
                    Text(preview).font(.footnote).textSelection(.enabled)
                }.accessibilityIdentifier("promptPreview")
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("模式提示词").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            VStack {
                if let error { ErrorBanner(message: error) }
                if let notice {
                    Label(notice, systemImage: "checkmark.circle.fill").font(.subheadline)
                        .foregroundStyle(theme.accent).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).accessibilityIdentifier("promptSavedNotice")
                }
            }.padding(.horizontal, 16).background(Theme.background)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    editing = false
                    var settings = store.settings
                    for mode in TranslationMode.allCases { settings.setPrompt(drafts[mode.rawValue] ?? "", for: mode) }
                    do { try store.save(settings, keys: [:]); error = nil; notice = "三种模式的提示词已保存。" }
                    catch { self.error = error.localizedDescription; notice = nil }
                }.fontWeight(.semibold).accessibilityIdentifier("savePromptButton")
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { editing = false } }
        }
        .onChange(of: selectedMode) { _, _ in editing = false; notice = nil; error = nil }
        .onAppear {
            guard !loaded else { return }
            drafts = store.settings.modePrompts; selectedMode = store.settings.mode; loaded = true
        }
    }
    private func token(_ token: String, _ label: String) -> some View {
        LabeledContent(label) { Text(token).font(.caption.monospaced()).foregroundStyle(theme.accent) }
    }
}
