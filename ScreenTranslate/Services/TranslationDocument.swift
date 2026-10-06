import Foundation

/// Self-contained full reader. Model and OCR output are escaped as text, never executed.
enum TranslationDocument {
    static func html(_ result: TranslationResult, settings: AppSettings = AppSettings()) -> Data {
        let reader = settings.reader
        let blocks = result.blocks ?? ReadingBlock.plainText(result.translated)
        var content = "", inList = false, inTable = false
        for block in blocks {
            let table = block.kind == .tableHeader || block.kind == .tableRow
            if !table && inTable { content += "</tbody></table>"; inTable = false }
            if block.kind == .listItem && !inList { content += "<ul>"; inList = true }
            if block.kind != .listItem && inList { content += "</ul>"; inList = false }
            if table && !inTable { content += "<table><tbody>"; inTable = true }
            switch block.kind {
            case .heading: content += "<h1>\(escaped(block.text))</h1>"
            case .listItem: content += "<li\(block.hasVisibleListMarker ? " class=\"numbered\"" : "")>\(escaped(block.listText))</li>"
            case .field:
                if let parts = block.fieldParts {
                    content += "<div class=\"field-row\"><span class=\"field-label\">\(escaped(parts.label))</span><span class=\"field-value\">\(escaped(parts.value))</span></div>"
                } else { content += "<p class=\"field\">\(escaped(block.text))</p>" }
            case .paragraph: content += "<p>\(escaped(block.text))</p>"
            case .tableHeader, .tableRow:
                let tag = block.kind == .tableHeader ? "th" : "td"
                content += "<tr>" + (block.tableCells ?? [block.text]).map {
                    "<\(tag)\(tag == "th" ? " scope=\"col\"" : "")>\(escaped($0))</\(tag)>"
                }.joined() + "</tr>"
            }
        }
        if inList { content += "</ul>" }
        if inTable { content += "</tbody></table>" }
        // Keep operational/quality diagnostics in the app and history, not in
        // the document's reading area. Native HTML disclosure needs no script.
        let visual = result.imageMode == .visual || result.mode == .visual
        let hasOriginal = !result.original.isEmpty && (!visual || result.visualOCR == true)
        let original = hasOriginal
            ? "<details class=\"original\"\(reader.showOriginal ? " open" : "")><summary>查看原文</summary><p>\(escaped(result.original))</p></details>" : ""
        let colorScheme: String
        switch settings.appearance { case .system: colorScheme = "light dark"; case .light: colorScheme = "light"; case .dark: colorScheme = "dark" }
        let base = settings.accentTheme == .custom ? settings.customAccent : settings.accentTheme.color
        func rgb(_ color: ThemeRGB) -> String {
            let c = color.normalized
            return "rgb(\(Int((c.red * 255).rounded())),\(Int((c.green * 255).rounded())),\(Int((c.blue * 255).rounded())))"
        }
        let light = "body { background:#faf9f7; color:#252523; } summary { color:\(rgb(base.accessible(on: .hex(0xFAF9F7)))); } .original { border-color:#ddd; }"
        let dark = "body { background:#171715; color:#f2f2ef; } summary { color:\(rgb(base.accessible(on: .hex(0x171715)))); } .original { border-color:#444; }"
        let appearance = settings.appearance == .dark ? dark : light + (settings.appearance == .system ? "@media (prefers-color-scheme:dark) { \(dark) }" : "")
        let language: String
        switch result.target { case "Japanese", "日语", "日本語": language = "ja"; case "英语", "English": language = "en"; default: language = "zh-Hans" }
        let document = """
        <!doctype html><html lang="\(language)"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="\(colorScheme)">
        <title>读屏</title>
        <style>
        :root { color-scheme:\(colorScheme); }
        body { margin:0; padding:18px; font:\(reader.textSize.points)px/\(reader.spacing.htmlLineHeight) -apple-system,BlinkMacSystemFont,"Hiragino Sans","PingFang SC","Helvetica Neue",sans-serif; line-break:strict; word-break:normal; }
        main { max-width:640px; margin:auto; }
        h1,p,li { white-space:pre-wrap; overflow-wrap:anywhere; margin:0 0 \(reader.spacing.paragraph)px; }
        h1 { font-size:\(reader.textSize.points + 3)px; line-height:1.4; font-weight:600; }
        h1:not(:first-child) { margin-top:20px; } .original + h1 { margin-top:0; }
        ul { padding-left:1.2em; margin:0 0 \(reader.spacing.paragraph)px; } li { margin-bottom:8px; }
        li.numbered { list-style:none; margin-left:-1.2em; }
        .field { font-variant-numeric:tabular-nums; padding:4px 0; }
        .field-row { display:flex; flex-wrap:wrap; align-items:baseline; column-gap:16px; row-gap:4px; margin:0 0 \(reader.spacing.paragraph)px; }
        .field-label { flex:1 1 40%; min-width:0; overflow-wrap:anywhere; }
        .field-value { margin-left:auto; max-width:100%; white-space:pre-wrap; overflow-wrap:anywhere; text-align:right; font-weight:500; font-variant-numeric:tabular-nums; }
        table { border-collapse:collapse; width:100%; table-layout:fixed; margin:0 0 \(reader.spacing.paragraph)px; font-variant-numeric:tabular-nums; }
        td,th { padding:9px 8px; vertical-align:top; white-space:pre-wrap; overflow-wrap:anywhere; text-align:left; border-bottom:1px solid rgba(128,128,128,0.2); }
        td:first-child,th:first-child { padding-left:0; } td:last-child,th:last-child { padding-right:0; text-align:right; }
        th { font-weight:600; font-size:0.9em; }
        summary { cursor:pointer; font-size:0.85em; min-height:44px; display:list-item; align-content:center; }
        .original { margin-bottom:18px; padding-bottom:4px; border-bottom:1px solid; }
        .original p { margin-top:12px; font-size:0.9em; }
        \(appearance)
        </style></head><body><main>\(original)\(content)</main></body></html>
        """
        return Data(document.utf8)
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
