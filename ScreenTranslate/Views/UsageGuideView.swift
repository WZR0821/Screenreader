import SwiftUI

struct UsageGuideView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { ShortcutGuideContent() } label: {
                    Label("操作按钮 · 三步设置", systemImage: "button.programmable")
                }.accessibilityIdentifier("actionButtonInstructionsLink")
            }
            Section("日常使用") {
                DisclosureGroup("翻译服务") {
                    Text("在“设置 → 翻译”选择 AI 翻译或系统翻译。系统翻译无需密钥，仅支持 App 内快速模式；API 支持三种模式，请在“API 设置”填写服务商、模型与密钥。")
                }
                DisclosureGroup("文字与图片") {
                    Text("快速模式完整简译；专业模式保留标题、段落、列表和价格关系，两者只发送文字。识图模式发送压缩图片，解释文字及画面大意。")
                    Text("通过“核对识别文字”可先修改识字结果。文字不清晰时可用识图模式重试；无法确认的文字不应猜测补全。")
                }
                DisclosureGroup("阅读与记录") {
                    Text("译文支持滚动、复制与分享。点时钟打开可搜索的记录；“缓存与记录”可选择保留 10、30 或 100 条。“译文显示”可调整字号、间距及原文是否默认展开。")
                }
                DisclosureGroup("提示词与隐私") {
                    Text("在“模式提示词”分别设置三种模式的要求。语言和模式同步用于 App 与操作按钮。系统翻译不使用提示词或术语表。")
                    Text("API 密钥保存在本机钥匙串；记录只保存文字，不保存截图。只有识图模式上传图片，服务商可能按用量收费。")
                }
            }
        }.font(.subheadline).navigationTitle("使用说明").navigationBarTitleDisplayMode(.inline)
    }
}
