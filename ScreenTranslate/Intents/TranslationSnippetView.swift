import SwiftUI

struct TranslationSnippetView: View {
    let result: TranslationResult?
    let error: String?
    let saved: Bool
    var legacyScreenshot: Bool = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(result == nil ? "暂时无法翻译" : (legacyScreenshot ? "旧版预览" : "读屏"), systemImage: result == nil ? "exclamationmark.circle" : "text.viewfinder")
                .font(.headline)
            if let result {
                let preview = TranslationFormatting.preview(result.translated, limit: typeSize.isAccessibilitySize ? 65 : 120)
                Text("\(result.sourceLanguages) → \(result.target) · \(result.imageMode == .visual ? "识图预览" : "译文预览")")
                    .font(.caption).foregroundStyle(.secondary)
                if let warning = result.warning {
                    Text(warning).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(preview.text + (preview.shortened ? "…" : "")).font(.body).lineSpacing(2)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                if legacyScreenshot {
                    Text("请在读屏的“设置 → 操作按钮”安装全文快捷指令，再到 iPhone 设置绑定。更新 App 不会更改旧快捷指令。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(preview.shortened ? "在此操作后添加“快速查看”，即可滚动阅读全文。" : (saved ? "译文已保存。" : "全文已返回快捷指令。"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            } else {
                Text(error ?? "请稍后重试。").font(.body)
                Text("请检查读屏设置后重新运行。").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16)
    }
}
