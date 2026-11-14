import SwiftUI

extension ReaderPreferences {
    func displayFont(scale: Double = 1, heading: Bool = false) -> Font {
        let design: Font.Design
        switch font { case .system: design = .default; case .serif: design = .serif; case .rounded: design = .rounded }
        return .system(size: (fontSize + (heading ? 3 : 0)) * scale,
                       weight: heading ? .semibold : (emphasized ? .medium : .regular), design: design)
    }
}

struct ReaderSettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var error: String?
    @ScaledMetric(relativeTo: .body) private var textScale = 1.0
    private var reader: ReaderPreferences { store.settings.reader }

    var body: some View {
        Form {
            Section {
                ScrollView {
                    VStack(alignment: .leading, spacing: reader.paragraphSpacing) {
                        Text("让译文读起来更舒服").font(reader.displayFont(scale: textScale, heading: true))
                        Text("保留原文的段落与重点。字号、行距和段距，可以按你的阅读习惯分别调整。")
                        Text("• 标题清晰，列表有序\n• 随时展开原文，逐段核对")
                    }
                    .font(reader.displayFont(scale: textScale)).lineSpacing(reader.lineSpacing * textScale)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
                // A growing preview must not move a slider out from under the finger.
                .frame(height: 190 * min(textScale, 1.5))
                .accessibilityIdentifier("readerPreview")
            } header: { Text("实时预览 · 可上下滚动").sectionTitle() } footer: {
                Text("即选即保存，应用于阅读模式、翻译记录与下次全文窗口。原图直译按文字区域自动适配字号，可放大查看。")
            }
            Section {
                Toggle("日语假名注音", isOn: Binding(get: { reader.showJapaneseFurigana }, set: { value in update { $0.showJapaneseFurigana = value } }))
                    .accessibilityIdentifier("readerFuriganaToggle")
                ScrollView {
                    JapaneseTranslationText(text: "日本語の文章を読む。", target: "日语", reader: reader, textScale: textScale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("readerFuriganaPreview")
                }.frame(height: 64 * min(textScale, 1.5))
            } header: { Text("日语注音").sectionTitle() }
              footer: { Text("在日语译文的汉字上方显示小号平假名，可在翻译页随时切换。读音由本机生成，多音字和姓名请结合语境核对。") }
            Section {
                Picker("字号预设", selection: sizePreset) {
                    ForEach(ReaderTextSize.allCases) { Text($0.title).tag(Optional($0)) }
                    Text("自定义").tag(nil as ReaderTextSize?)
                }.pickerStyle(.segmented).accessibilityIdentifier("readerTextSizePicker")
                adjustment("字号", value: reader.fontSize, range: ReaderPreferences.fontSizeRange,
                           id: "readerFontSize") { value in update { $0.customFontSize = value } }
                Picker("字体", selection: Binding(get: { reader.font }, set: { value in update { $0.font = value } })) {
                    ForEach(ReaderFont.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("readerFontPicker")
                Toggle("加重正文", isOn: Binding(get: { reader.emphasized }, set: { value in update { $0.emphasized = value } }))
                    .accessibilityIdentifier("readerEmphasisToggle")
            } header: { Text("字号与字体").sectionTitle() }
            Section {
                Picker("间距预设", selection: spacingPreset) {
                    ForEach(ReaderSpacing.allCases) { Text($0.title).tag(Optional($0)) }
                    Text("自定义").tag(nil as ReaderSpacing?)
                }.pickerStyle(.segmented).accessibilityIdentifier("readerSpacingPicker")
                adjustment("行间距", value: reader.lineSpacing, range: ReaderPreferences.lineSpacingRange,
                           id: "readerLineSpacing") { value in update { $0.customLineSpacing = value } }
                adjustment("段落间距", value: reader.paragraphSpacing, range: ReaderPreferences.paragraphSpacingRange,
                           id: "readerParagraphSpacing") { value in update { $0.customParagraphSpacing = value } }
            } header: { Text("阅读间距").sectionTitle() } footer: {
                Text("行间距是在字体默认行高之外增加的留白；段落间距控制相邻段落之间的距离。字体会按语言自动回退到支持的字形。")
            }
            Section {
                Toggle("默认展开原文", isOn: Binding(get: { reader.showOriginal }, set: { value in update { $0.showOriginal = value } }))
                    .accessibilityIdentifier("readerOriginalToggle")
                Button("恢复默认排版") { update { $0 = ReaderPreferences() } }
                    .accessibilityIdentifier("resetReaderPreferences")
            } header: { Text("原文与恢复").sectionTitle() }
            if let error { Section { ErrorBanner(message: error) } }
        }
        .settingsList()
        .navigationTitle("译文显示").navigationBarTitleDisplayMode(.inline)
    }

    private var sizePreset: Binding<ReaderTextSize?> {
        Binding(get: { reader.customFontSize == nil ? reader.textSize : nil }, set: { value in
            update {
                if let value { $0.textSize = value; $0.customFontSize = nil }
                else { $0.customFontSize = $0.fontSize }
            }
        })
    }
    private var spacingPreset: Binding<ReaderSpacing?> {
        Binding(get: { reader.customLineSpacing == nil && reader.customParagraphSpacing == nil ? reader.spacing : nil }, set: { value in
            update {
                if let value { $0.spacing = value; $0.customLineSpacing = nil; $0.customParagraphSpacing = nil }
                else { $0.customLineSpacing = $0.lineSpacing; $0.customParagraphSpacing = $0.paragraphSpacing }
            }
        })
    }

    private func adjustment(_ title: String, value: Double, range: ClosedRange<Double>, id: String,
                            set: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) pt").monospacedDigit().foregroundStyle(.secondary).accessibilityIdentifier(id + "Value")
            }
            Slider(value: Binding(get: { value }, set: set), in: range, step: 1)
                .accessibilityLabel(title).accessibilityValue("\(Int(value)) 点")
                .accessibilityIdentifier(id + "Slider")
        }.padding(.vertical, 4)
    }

    private func update(_ change: (inout ReaderPreferences) -> Void) {
        var settings = store.settings
        change(&settings.reader)
        do { try store.save(settings, keys: [:]); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
