import Foundation

/// Self-contained full reader. Model and OCR output are escaped as text, never executed.
enum TranslationDocument {
    static func html(_ result: TranslationResult, settings: AppSettings = AppSettings(), image: SourceImagePresentation? = nil) -> Data {
        let reader = settings.reader
        let japanese = JapaneseFurigana.isJapanese(target: result.target)
        // The action button gives no preview: a target changed by 语言优先级 is explained here.
        let targetNote = result.targetNote.map { "<div class=\"target-note\">\(escaped($0))</div>" } ?? ""
        // Include readings even when initially hidden so the standalone reader can toggle without a network request.
        func rendered(_ text: String) -> String {
            guard japanese else { return escaped(text) }
            let source = text as NSString
            var output = "", cursor = 0
            for annotation in JapaneseFurigana.annotations(for: text) {
                output += escaped(source.substring(with: NSRange(location: cursor, length: annotation.range.location - cursor)))
                output += "<ruby>\(escaped(source.substring(with: annotation.range)))<rt aria-hidden=\"true\">\(escaped(annotation.reading))</rt></ruby>"
                cursor = NSMaxRange(annotation.range)
            }
            return output + escaped(source.substring(from: cursor))
        }
        let blocks = result.blocks ?? ReadingBlock.plainText(result.translated)
        var content = "", inList = false, inTable = false
        for block in blocks {
            let table = block.kind == .tableHeader || block.kind == .tableRow
            if !table && inTable { content += "</tbody></table></div>"; inTable = false }
            if block.kind == .listItem && !inList { content += "<ul>"; inList = true }
            if block.kind != .listItem && inList { content += "</ul>"; inList = false }
            if table && !inTable {
                let columns = block.tableCells?.count ?? 0
                let minimum = columns > 3 ? " style=\"min-width:\(columns * 112)px\"" : ""
                content += "<div class=\"table-scroll\" role=\"region\" aria-label=\"表格，可左右滑动\" tabindex=\"0\"><table\(minimum)><tbody>"
                inTable = true
            }
            switch block.kind {
            case .heading: content += "<h1>\(rendered(block.text))</h1>"
            case .listItem: content += "<li\(block.hasVisibleListMarker ? " class=\"numbered\"" : "")>\(rendered(block.listText))</li>"
            case .field:
                if let parts = block.fieldParts {
                    content += "<div class=\"field-row\"><span class=\"field-label\">\(rendered(parts.label))</span><span class=\"field-value\">\(rendered(parts.value))</span></div>"
                } else { content += "<p class=\"field\">\(rendered(block.text))</p>" }
            case .paragraph: content += "<p>\(rendered(block.text))</p>"
            case .tableHeader, .tableRow:
                let tag = block.kind == .tableHeader ? "th" : "td"
                content += "<tr>" + (block.tableCells ?? [block.text]).map {
                    "<\(tag)\(tag == "th" ? " scope=\"col\"" : "")>\(rendered($0))</\(tag)>"
                }.joined() + "</tr>"
            }
        }
        if inList { content += "</ul>" }
        if inTable { content += "</tbody></table></div>" }
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
        let light = ":root { --paper:#fff; --ink:#1c1c1e; --muted:#636366; --line:#e5e5ea; --tint:#f2f2f7; --accent:\(rgb(base.accessible(on: .hex(0xFFFFFF)))); }"
        let dark = ":root { --paper:#1c1c1e; --ink:#f2f2f7; --muted:#aeaeb2; --line:#38383a; --tint:#2c2c2e; --accent:\(rgb(base.accessible(on: .hex(0x1C1C1E)))); }"
        let appearance = settings.appearance == .dark ? dark : light + (settings.appearance == .system ? "@media (prefers-color-scheme:dark) { \(dark) }" : "")
        let language: String
        switch result.target { case "Japanese", "日语", "日本語": language = "ja"; case "英语", "English": language = "en"; default: language = "zh-Hans" }
        let rubyControl = japanese
            ? "<input type=\"checkbox\" id=\"show-furigana\"\(reader.showJapaneseFurigana ? " checked" : "")><label for=\"show-furigana\">日语注音</label>" : ""
        let imageContent = image.map { ImageTranslationDocument.fragment(result, image: $0, rendered: rendered) } ?? ""
        let document = """
        <!doctype html><html lang="\(language)"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="color-scheme" content="\(colorScheme)">
        <title>读屏</title>
        <style>
        :root { color-scheme:\(colorScheme); }
        body { margin:0; padding:20px max(20px, env(safe-area-inset-right)) max(24px, env(safe-area-inset-bottom)) max(20px, env(safe-area-inset-left)); background:var(--paper); color:var(--ink); -webkit-text-size-adjust:100%; font:\(reader.fontSize)px/\(reader.htmlLineHeight) \(reader.font.cssFamily); font-weight:\(reader.emphasized ? 500 : 400); line-break:strict; word-break:normal; }
        .reader { max-width:680px; margin:auto; }
        .reader-header { display:flex; flex-wrap:wrap; justify-content:space-between; gap:8px; padding-bottom:16px; margin-bottom:20px; border-bottom:1px solid var(--line); font:500 13px/1.5 -apple-system, BlinkMacSystemFont, sans-serif; color:var(--muted); }
        .reader-header strong { color:var(--ink); font-weight:600; }
        .target-note { margin:-6px 0 18px; font:400 13px/1.5 -apple-system, BlinkMacSystemFont, sans-serif; color:var(--muted); }
        main { margin:0; }
        h1,p,li { white-space:pre-wrap; overflow-wrap:anywhere; margin:0 0 \(reader.paragraphSpacing)px; }
        h1 { font-size:\(reader.fontSize + 3)px; font-weight:600; }
        h1:not(:first-child) { margin-top:20px; } .original + h1 { margin-top:0; }
        ul { padding-left:1.2em; margin:0; }
        li.numbered { list-style:none; margin-left:-1.2em; }
        .field { font-variant-numeric:tabular-nums; padding:4px 0; }
        .field-row { display:flex; flex-wrap:wrap; align-items:baseline; column-gap:16px; row-gap:4px; margin:0 0 \(reader.paragraphSpacing)px; }
        .field-label { flex:1 1 40%; min-width:0; overflow-wrap:anywhere; }
        .field-value { margin-left:auto; max-width:100%; white-space:pre-wrap; overflow-wrap:anywhere; text-align:right; font-weight:500; font-variant-numeric:tabular-nums; }
        table { border-collapse:collapse; width:100%; table-layout:fixed; margin:0 0 \(reader.paragraphSpacing)px; font-variant-numeric:tabular-nums; }
        .table-scroll { max-width:100%; overflow-x:auto; -webkit-overflow-scrolling:touch; }
        td,th { padding:9px 8px; vertical-align:top; white-space:pre-wrap; overflow-wrap:anywhere; text-align:left; border-bottom:1px solid rgba(128,128,128,0.2); }
        td:first-child,th:first-child { padding-left:0; } td:last-child,th:last-child { padding-right:0; text-align:right; }
        th { font-weight:600; font-size:0.9em; }
        summary { cursor:pointer; color:var(--accent); font-size:0.85em; min-height:44px; display:list-item; align-content:center; }
        .original { margin-top:24px; padding-top:8px; border-top:1px solid var(--line); color:var(--muted); }
        .original p { margin-top:12px; font-size:0.9em; }
        ruby { display:inline; ruby-position:over; ruby-align:center; }
        rt { display:none; font-size:0.5em; font-weight:400; -webkit-user-select:none; user-select:none; }
        #show-furigana:checked ~ main ruby { display:revert; }
        #show-furigana:checked ~ main rt { display:revert; }
        #show-furigana { position:absolute; width:1px; height:1px; opacity:0; }
        #show-furigana:checked + label { color:var(--accent); border-color:var(--accent); }
        #show-furigana:focus-visible + label { outline:2px solid var(--accent); outline-offset:3px; }
        label[for="show-furigana"] { display:inline-flex; align-items:center; min-height:44px; box-sizing:border-box; margin:0 0 18px; padding:0 16px; border:1px solid var(--line); border-radius:22px; background:var(--tint); color:var(--muted); font:500 14px/1.5 -apple-system, BlinkMacSystemFont, sans-serif; cursor:pointer; }
        \(appearance)
        \(imageContent.isEmpty ? "" : ImageTranslationDocument.css)
        </style></head><body><div class="reader"><header class="reader-header"><strong>读屏 · 译文</strong><span>\(escaped(result.sourceLanguages)) → \(escaped(result.target))</span></header>\(targetNote)\(rubyControl)\(imageContent)<main>\(content)</main>\(original)</div></body></html>
        """
        return Data(document.utf8)
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
