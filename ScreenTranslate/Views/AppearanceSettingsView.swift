import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.appTheme) private var theme
    @State private var error: String?

    var body: some View {
        Form {
            Section("显示方式") {
                Picker("显示方式", selection: Binding(get: { store.settings.appearance }, set: { appearance in
                    update { $0.appearance = appearance }
                })) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("appearancePicker")
            }
            Section {
                ForEach(AccentTheme.allCases) { palette in
                    Button {
                        update { $0.accentTheme = palette }
                    } label: {
                        HStack(spacing: 14) {
                            Circle().fill(Color(uiColor: UIColor(rgb: palette == .custom ? store.settings.customAccent : palette.color)))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 1))
                            Text(palette.title).foregroundStyle(.primary)
                            Spacer()
                            if store.settings.accentTheme == palette {
                                Image(systemName: "checkmark").foregroundStyle(theme.accent)
                            }
                        }.frame(minHeight: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("accent-\(palette.rawValue)")
                        .accessibilityValue(store.settings.accentTheme == palette ? "已选" : "未选")
                }
                if store.settings.accentTheme == .custom {
                    ColorPicker("选择颜色", selection: Binding(get: { Color(uiColor: UIColor(rgb: store.settings.customAccent)) }, set: { color in
                        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
                        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
                        update { $0.customAccent = .init(red: Double(r), green: Double(g), blue: Double(b)) }
                    }), supportsOpacity: false).accessibilityIdentifier("customColorPicker")
                }
            } header: { Text("主题色") } footer: {
                Text("颜色用于按钮和选中状态，即选即保存。为保证可读性，过浅或过深的颜色会自动调整。")
            }
            Section("阅读预览") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("让内容成为主角。").font(.title3.weight(.medium))
                    Text("清晰阅读，轻松翻译。").foregroundStyle(.secondary)
                    Text("翻译").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(theme.onAccent).background(theme.accent, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("翻译按钮颜色预览")
                }.padding(.vertical, 8)
            }
            if let error { Section { ErrorBanner(message: error) } }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("外观与颜色").navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ change: (inout AppSettings) -> Void) {
        var settings = store.settings
        change(&settings)
        do { try store.save(settings, keys: [:]); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
