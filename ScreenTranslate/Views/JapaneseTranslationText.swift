import SwiftUI
import CoreText

/// SwiftUI Text discards Core Text ruby attributes; use the same typesetter for measurement and drawing.
struct JapaneseTranslationText: View {
    let text: String
    let target: String
    let reader: ReaderPreferences
    var textScale: Double = 1
    var heading = false
    var semibold = false
    var medium = false
    var alignment: NSTextAlignment = .natural
    @Environment(\.colorScheme) private var colorScheme
    @State private var readings: [JapaneseFurigana.Annotation] = []
    @State private var annotatedText = ""
    private var enabled: Bool { reader.showJapaneseFurigana && JapaneseFurigana.isJapanese(target: target) }

    var body: some View {
        Group {
            if enabled, annotatedText == text, !readings.isEmpty {
                let content = RubyTextLayout.attributed(text, annotations: readings,
                    reader: reader, scale: textScale, heading: heading, semibold: semibold, medium: medium,
                    alignment: alignment, dark: colorScheme == .dark)
                RubyTextRepresentable(content: content)
                    .alignmentGuide(.firstTextBaseline) { RubyTextLayout.firstBaseline(content, width: $0.width) }
                    .accessibilityLabel(text).accessibilityValue("假名注音已开启")
                    .contextMenu { Button("复制这段译文", systemImage: "doc.on.doc") { UIPasteboard.general.string = text } }
            } else {
                Text(text).font(reader.displayFont(scale: textScale, heading: heading))
                    .fontWeight(semibold ? .semibold : (heading ? .semibold : (reader.emphasized || medium ? .medium : .regular)))
                    .lineSpacing(reader.lineSpacing * textScale)
                    .multilineTextAlignment(alignment == .right ? .trailing : .leading)
                    .textSelection(.enabled)
            }
        }.fixedSize(horizontal: false, vertical: true)
            .task(id: enabled ? text : nil) {
                guard enabled else { return }
                let snapshot = text
                let value = await Task.detached(priority: .userInitiated) { JapaneseFurigana.annotations(for: snapshot) }.value
                guard !Task.isCancelled else { return }
                readings = value; annotatedText = snapshot
            }
    }
}

enum RubyTextLayout {
    static func firstBaseline(_ content: NSAttributedString, width: CGFloat) -> CGFloat {
        let setter = CTFramesetterCreateWithAttributedString(content)
        let width = max(1, width.isFinite ? width : 320)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: width, height: 10_000_000), nil)
        let height = ceil(size.height)
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(x: 0, y: 0, width: width, height: max(1, height)), transform: nil), nil)
        guard CFArrayGetCount(CTFrameGetLines(frame)) > 0 else { return 0 }
        var origin = CGPoint.zero
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 1), &origin)
        return height - origin.y + 2
    }

    static func attributed(_ text: String, annotations: [JapaneseFurigana.Annotation], reader: ReaderPreferences,
                           scale: Double = 1, heading: Bool = false, semibold: Bool = false, medium: Bool = false,
                           alignment: NSTextAlignment = .natural, dark: Bool = false) -> NSAttributedString {
        let size = (reader.fontSize + (heading ? 3 : 0)) * scale
        let weight: UIFont.Weight = heading || semibold ? .semibold : (reader.emphasized || medium ? .medium : .regular)
        let design: UIFontDescriptor.SystemDesign = reader.font == .serif ? .serif : (reader.font == .rounded ? .rounded : .default)
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let font = UIFont(descriptor: base.fontDescriptor.withDesign(design) ?? base.fontDescriptor, size: size)
        let color = UIColor.label.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = reader.lineSpacing * scale; paragraph.alignment = alignment
        let value = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph,
            NSAttributedString.Key(kCTLanguageAttributeName as String): "ja"])
        for annotation in annotations where NSMaxRange(annotation.range) <= value.length {
            let ruby = CTRubyAnnotationCreateWithAttributes(.center, .none, .before, annotation.reading as CFString,
                [kCTRubyAnnotationSizeFactorAttributeName: 0.5, kCTForegroundColorAttributeName: color.cgColor] as CFDictionary)
            value.addAttribute(NSAttributedString.Key(kCTRubyAnnotationAttributeName as String), value: ruby, range: annotation.range)
        }
        return value
    }
}

private struct RubyTextRepresentable: UIViewRepresentable {
    let content: NSAttributedString
    func makeUIView(context: Context) -> RubyTextCanvas { RubyTextCanvas() }
    func updateUIView(_ uiView: RubyTextCanvas, context: Context) { uiView.setContent(content) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RubyTextCanvas, context: Context) -> CGSize? {
        uiView.measuredSize(width: proposal.width ?? 320)
    }
}

final class RubyTextCanvas: UIView {
    private(set) var content = NSAttributedString(string: "")
    private var framesetter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: ""))
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear; isAccessibilityElement = true; accessibilityTraits = .staticText
        contentMode = .redraw
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setContent(_ content: NSAttributedString) {
        guard !self.content.isEqual(to: content) else { return }
        self.content = content; framesetter = CTFramesetterCreateWithAttributedString(content)
        accessibilityLabel = content.string
        invalidateIntrinsicContentSize(); setNeedsDisplay()
    }
    func measuredSize(width: CGFloat) -> CGSize {
        let width = max(1, width.isFinite ? width : 320)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil,
            CGSize(width: width, height: 10_000_000), nil)
        return CGSize(width: width, height: ceil(size.height) + 4)
    }
    func textFrame(size: CGSize) -> CTFrame {
        CTFramesetterCreateFrame(framesetter, CFRange(),
            CGPath(rect: CGRect(x: 0, y: 2, width: max(1, size.width), height: max(1, size.height - 4)), transform: nil), nil)
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState(); context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        CTFrameDraw(textFrame(size: bounds.size), context)
        context.restoreGState()
    }
}

struct FuriganaToggleButton: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var store: SettingsStore
    @State private var error: String?
    var body: some View {
        Button {
            var settings = store.settings; settings.reader.showJapaneseFurigana.toggle()
            do { try store.save(settings, keys: [:]) } catch { self.error = error.localizedDescription }
        } label: {
            Text("注音").font(.caption.weight(.medium))
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(store.settings.reader.showJapaneseFurigana ? theme.accent.opacity(0.10) : Theme.background,
                    in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain)
            .foregroundStyle(store.settings.reader.showJapaneseFurigana ? theme.accent : .secondary)
            .accessibilityLabel("日语假名注音").accessibilityValue(store.settings.reader.showJapaneseFurigana ? "开启" : "关闭")
            .accessibilityHint("切换日语译文汉字上方的假名，不需要重新翻译")
            .accessibilityIdentifier("translationFuriganaToggle")
            .alert("未能保存设置", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好") { error = nil }
            } message: { Text(error ?? "") }
    }
}
