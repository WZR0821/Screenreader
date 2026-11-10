import Foundation
import UIKit

/// CSS-only controls work in Quick Look without scripts, network access or a
/// live connection to the app. Every source / translation string is escaped.
enum ImageTranslationDocument {
    static func fragment(_ result: TranslationResult, image: SourceImagePresentation,
                         rendered: (String) -> String) -> String {
        let items = ImageTranslationLayout.items(in: result)
        guard !items.isEmpty else { return "" }
        let width = 360.0, height = 360 * Double(image.height) / Double(image.width)
        func number(_ value: Double) -> String { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value) }
        let overlays = items.map { item in
            let box = item.box
            let size = CGSize(width: max(1, box.width * width + 2), height: max(1, box.height * height + 3))
            let fit = ImageOverlayTypography.fitted(item: item, size: size, color: .black,
                annotations: JapaneseFurigana.isJapanese(target: result.target) ? JapaneseFurigana.annotations(for: item.text) : [])
            return """
            <label class="overlay-word\(item.vertical ? " vertical-word" : "")" for="image-review-\(item.id)" style="left:calc(\(number(box.x * 100))% - 0.556cqw);top:calc(\(number((1 - box.y - box.height) * 100))% - 0.556cqw);width:calc(\(number(box.width * 100))% + 1.112cqw);height:calc(\(number(box.height * 100))% + 1.112cqw);font-size:\(number(Double(fit.fontSize) / width * 100))cqw;font-weight:\(item.heading ? 600 : 400)">\(rendered(item.text))\(fit.truncated ? "<span class=overflow-mark>…</span>" : "")</label>
            """
        }.joined()
        let details = items.map { item in
            """
            <input type="radio" class="presentation-input image-review-choice" name="image-review" id="image-review-\(item.id)">
            <section class="image-detail" role="dialog" aria-label="核对译文">
            <div class="image-detail-card"><header><strong>核对译文</strong><label for="image-review-closed">关闭核对</label></header>
            <h2>原文</h2><p>\(TranslationDocument.escaped(item.original))</p><h2>\(TranslationDocument.escaped(result.target))译文</h2><p>\(rendered(item.text))</p></div></section>
            """
        }.joined()
        return """
        <input class="presentation-input" type="radio" name="presentation" id="presentation-image" checked>
        <input class="presentation-input" type="radio" name="presentation" id="presentation-reading">
        <div class="presentation-control" role="group" aria-label="译文显示方式"><label for="presentation-image">原图直译</label><label for="presentation-reading">阅读</label></div>
        <section class="image-pane"><input class="presentation-input" type="checkbox" id="image-original">
        <div class="image-actions"><span>点按译文核对 · 可双指缩放</span><label for="image-original">原图对照</label></div>
        <div class="image-canvas" style="aspect-ratio:\(image.width)/\(image.height)">
        <img alt="原始截图" width="\(image.width)" height="\(image.height)" src="data:image/jpeg;base64,\(image.data.base64EncodedString())">
        <div class="image-overlay">\(overlays)</div></div>
        <div class="image-review-controls"><input type="radio" class="presentation-input" name="image-review" id="image-review-closed" checked>\(details)</div>
        </section>
        """
    }

    static let css = """
    .presentation-input { position:absolute; width:1px; height:1px; opacity:0; }
    .presentation-control { display:flex; padding:3px; border-radius:10px; background:var(--tint); margin-bottom:8px; font:500 14px/1.3 -apple-system,sans-serif; }
    .presentation-control label { flex:1; text-align:center; padding:12px 6px; cursor:pointer; border-radius:8px; }
    #presentation-image:checked ~ .presentation-control label[for="presentation-image"], #presentation-reading:checked ~ .presentation-control label[for="presentation-reading"] { background:var(--paper); box-shadow:0 1px 3px #0002; }
    .presentation-input:focus-visible ~ .presentation-control { outline:2px solid var(--accent); }
    #presentation-image:checked ~ main, #presentation-image:checked ~ .original { display:none; }
    #presentation-reading:checked ~ .image-pane { display:none; }
    .image-actions { display:flex; justify-content:space-between; gap:8px; align-items:center; font:12px/1.5 -apple-system,sans-serif; color:var(--muted); }
    .image-actions label { display:inline-flex; min-height:44px; align-items:center; padding:0 8px; cursor:pointer; }
    #image-original:checked ~ .image-actions label { color:var(--accent); font-weight:600; }
    .image-canvas { container-type:inline-size; position:relative; width:100%; overflow:hidden; border-radius:10px; background:var(--tint); }
    .image-canvas img { display:block; width:100%; height:auto; }
    .image-overlay { position:absolute; inset:0; width:100%; height:100%; }
    #image-original:checked ~ .image-canvas .image-overlay, #image-original:checked ~ .image-review-controls { display:none; }
    .overlay-word { display:block; position:absolute; box-sizing:border-box; padding:0.139cqw 0.278cqw; overflow:hidden; background:var(--paper); color:var(--ink); border-radius:2px; cursor:pointer; font-family:-apple-system,sans-serif; line-height:1.15; white-space:pre-wrap; overflow-wrap:anywhere; }
    .vertical-word { writing-mode:vertical-rl; text-orientation:mixed; }
    .overflow-mark { position:absolute; bottom:0; right:0; background:var(--paper); line-height:1; }
    .image-detail { display:none; position:fixed; inset:0; background:#0005; z-index:10; padding:24px 16px; align-items:center; justify-content:center; }
    .image-review-choice:checked + .image-detail { display:flex; }
    .image-detail-card { box-sizing:border-box; width:100%; max-width:560px; max-height:85vh; overflow:auto; background:var(--paper); border-radius:22px; padding:20px; font-size:18px; }
    .image-detail header { display:flex; justify-content:space-between; align-items:center; gap:12px; }
    .image-detail header label { display:inline-flex; align-items:center; min-height:44px; color:var(--accent); cursor:pointer; }
    .image-detail h2 { font-size:13px; color:var(--muted); font-weight:500; margin:16px 0 8px; }
    #show-furigana:checked ~ .image-pane ruby { display:revert; }
    #show-furigana:checked ~ .image-pane rt { display:revert; }
    """
}
