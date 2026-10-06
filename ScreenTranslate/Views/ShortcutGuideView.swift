import SwiftUI

struct ShortcutGuideContent: View {
    var body: some View {
        List {
            Section {
                Text("长按操作按钮，即可截屏、翻译并打开可滚动的全文窗口。")
                Text("已在使用“屏译全文”？无需重建，更新 App 后原来的快捷指令和按钮绑定仍可使用。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                if let file = Bundle.main.url(forResource: "读屏全文", withExtension: "shortcut") {
                    ShareLink(item: file) { Label("安装“读屏全文”", systemImage: "square.and.arrow.down") }
                        .accessibilityIdentifier("importFullShortcut")
                }
                Text("点“安装” → 选择“快捷指令” → “添加快捷指令” → “完成”。")
            } header: { Text("1 · 安装快捷指令") } footer: {
                Text("已连接好三个操作。分享菜单中找不到“快捷指令”时，可先存储到“文件”，再打开该文件。")
            }
            Section {
                Text("打开 iPhone“设置” → “操作按钮” → 滑到“快捷指令” → 选择“读屏全文”。")
            } header: { Text("2 · 绑定操作按钮") } footer: {
                Text("请选择完整的快捷指令，单独的翻译操作不会自动截屏和打开全文。")
            }
            Section {
                Text("解锁手机，打开待翻译页面，长按操作按钮。首次按提示允许权限；在结果窗口上下滑动，可读到最后一项。")
            } header: { Text("3 · 试一次") }
            Section {
                DisclosureGroup("查看原文与关闭窗口") {
                    Text("点“查看原文”展开或收起识别文字。点系统的“×”或“完成”关闭。工具栏隐藏时，可点空白处或滚动到顶部。工具栏、推荐应用及窗口高度由 iOS 控制。")
                }
                DisclosureGroup("选择翻译模式") {
                    Text("在“设置 → 翻译”选择默认模式；也可开启“每次运行时选择模式”并保存，原有“屏译全文”同样支持。操作按钮使用 API 翻译；系统翻译仅在 App 内运行。")
                }
                DisclosureGroup("只看到简短预览？") {
                    Text("请安装上方全文快捷指令。手动修改旧指令时，按顺序连接“截屏 → 读屏：翻译截图全文 → 快速查看”，后一项使用前一项的输出。保留原快捷指令名称可继续使用已有按钮绑定。")
                }
                DisclosureGroup("找不到 App，或总让选图片？") {
                    Text("先打开一次读屏，检查翻译操作的图片输入是否为“截屏”。若重签名改变了应用标识，请重新添加当前安装版本的“翻译截图全文”操作。")
                }
                Link(destination: URL(string: "shortcuts://")!) {
                    Label("打开快捷指令", systemImage: "arrow.up.forward.app")
                }.accessibilityIdentifier("openShortcutsFromGuide")
                Link("Apple 官方：为操作按钮设置快捷指令", destination: URL(string: "https://support.apple.com/guide/shortcuts/apdfea15680b/ios")!)
            } header: { Text("常见问题") }
        }.listStyle(.insetGrouped).font(.subheadline)
            .navigationTitle("操作按钮").navigationBarTitleDisplayMode(.inline)
    }
}
