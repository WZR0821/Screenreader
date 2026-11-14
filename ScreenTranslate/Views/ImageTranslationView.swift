import SwiftUI
import CoreText

struct ImageTranslationView: View {
    let data: Data
    let result: TranslationResult
    var isWorking: Bool
    let review: (Int) -> Void
    @Environment(\.appTheme) private var theme
    @State private var image: UIImage?
    @State private var pixels: ImageOverlayPalette.Pixels?
    @State private var failed = false
    @State private var showsOriginal = false
    @State private var expanded = false
    @State private var pendingReview: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("点按译文核对").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button { showsOriginal.toggle() } label: {
                    Label(showsOriginal ? "显示译文" : "查看原图", systemImage: showsOriginal ? "character.bubble" : "photo")
                        .font(.caption).frame(minHeight: 44)
                }.accessibilityIdentifier("imageOriginalToggle").accessibilityValue(showsOriginal ? "原图" : "译文")
                Button { expanded = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }.accessibilityLabel("放大原图直译").accessibilityIdentifier("expandImageTranslation")
                    .disabled(image == nil)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
            if let image {
                ImageTranslationCanvas(image: image, pixels: pixels, items: ImageTranslationLayout.items(in: result),
                    original: showsOriginal, reader: theme.settings.reader, target: result.target,
                    enabled: !isWorking, tapped: review)
                    .aspectRatio(image.size, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.06)))
                    .accessibilityIdentifier("imageTranslationCanvas")
                    .accessibilityHidden(expanded)
            } else if failed {
                ContentUnavailableView("原图暂时无法显示", systemImage: "photo", description: Text("可切换到阅读查看完整译文。"))
            } else {
                ProgressView("正在准备原图").frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task(id: data) {
            image = nil; pixels = nil; failed = false
            let prepared = await Task.detached(priority: .userInitiated) { () -> (SourceImagePresentation?, ImageOverlayPalette.Pixels?) in
                let presentation = SourceImagePresentation.prepare(data)
                return (presentation, presentation.flatMap { ImageOverlayPalette.Pixels(data: $0.data) })
            }.value
            guard !Task.isCancelled else { return }
            image = prepared.0.flatMap { UIImage(data: $0.data) }; pixels = prepared.1; failed = image == nil
        }
        .fullScreenCover(isPresented: $expanded, onDismiss: {
            if let id = pendingReview { pendingReview = nil; review(id) }
        }) {
            if let image {
                NavigationStack {
                    ZoomedTranslationImage(image: image, pixels: pixels, items: ImageTranslationLayout.items(in: result),
                        original: showsOriginal, reader: theme.settings.reader, target: result.target,
                        enabled: !isWorking) { id in pendingReview = id; expanded = false }
                        .background(Theme.background)
                        .navigationTitle("原图直译").navigationBarTitleDisplayMode(.inline)
                        .safeAreaInset(edge: .bottom) {
                            Text("双指缩放，双击还原 · 点按译文核对")
                                .font(.caption).foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity).background(.bar)
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(showsOriginal ? "显示译文" : "查看原图") { showsOriginal.toggle() }
                                    .accessibilityIdentifier("zoomOriginalToggle")
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { expanded = false }.accessibilityIdentifier("closeImageTranslation")
                            }
                        }
                }
            }
        }
    }
}

struct ImageTranslationCanvas: UIViewRepresentable {
    let image: UIImage
    var pixels: ImageOverlayPalette.Pixels?
    let items: [ImageTranslationLayout.Item]
    let original: Bool
    let reader: ReaderPreferences
    let target: String
    let enabled: Bool
    let tapped: (Int) -> Void
    func makeUIView(context: Context) -> ImageTranslationCanvasView { ImageTranslationCanvasView() }
    func updateUIView(_ view: ImageTranslationCanvasView, context: Context) {
        view.configure(image: image, pixels: pixels, items: items, original: original, reader: reader, target: target,
                       enabled: enabled, tapped: tapped)
    }
}

final class ImageTranslationCanvasView: UIView {
    private let photo = UIImageView()
    private var tiles: [ImageTranslationTile] = []
    private var items: [ImageTranslationLayout.Item] = []
    private var pixels: ImageOverlayPalette.Pixels?
    private var tapped: ((Int) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(photo); clipsToBounds = true
        photo.contentMode = .scaleToFill; photo.isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(image: UIImage, pixels: ImageOverlayPalette.Pixels? = nil, items: [ImageTranslationLayout.Item], original: Bool,
                   reader: ReaderPreferences, target: String, enabled: Bool, tapped: @escaping (Int) -> Void) {
        photo.image = image; self.tapped = tapped
        let visibleItems = original ? [] : items
        let rebuilt = self.items != visibleItems
        if rebuilt {
            tiles.forEach { $0.isHidden = true; $0.removeFromSuperview() }
            self.items = visibleItems
            tiles = visibleItems.map { item in
                let tile = ImageTranslationTile(item: item)
                tile.addTarget(self, action: #selector(selectTile(_:)), for: .touchUpInside)
                addSubview(tile); return tile
            }
        }
        if rebuilt || self.pixels != pixels {
            self.pixels = pixels
            // Read once per image and item; drawing never touches the pixels.
            for tile in tiles {
                tile.palette = pixels.flatMap { ImageOverlayPalette.sample($0, box: tile.item.box, line: tile.item.lineHeight,
                                                                           vertical: tile.item.vertical) }
            }
        }
        for tile in tiles {
            tile.isHidden = original; tile.isEnabled = enabled
            tile.isAccessibilityElement = !original
            tile.accessibilityElementsHidden = original
            tile.showFurigana = reader.showJapaneseFurigana && JapaneseFurigana.isJapanese(target: target)
        }
        isAccessibilityElement = original
        accessibilityElements = original ? [] : tiles
        accessibilityLabel = original ? "原始图片" : nil
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews(); photo.frame = bounds
        for tile in tiles {
            // Vision bounds hug the glyphs; the tile adds a margin in proportion
            // to the source line that covers antialiased edges.
            let placement = ImageTranslationLayout.placement(of: tile.item, in: bounds.size)
            tile.frame = placement.tile; tile.placement = placement.local
        }
    }
    @objc private func selectTile(_ tile: ImageTranslationTile) { tapped?(tile.item.blockID) }
}

final class ImageTranslationTile: UIControl {
    let item: ImageTranslationLayout.Item
    var showFurigana = false { didSet { if oldValue != showFurigana { setNeedsDisplay() } } }
    /// Measured from the tile's own corner.
    var placement: ImageTranslationLayout.Placement? { didSet { if oldValue != placement { setNeedsDisplay() } } }
    /// Colours of the screenshot under this item; nil until the image is read.
    var palette: ImageOverlayPalette? {
        didSet {
            guard oldValue != palette else { return }
            backgroundColor = palette.map { UIColor(rgb: $0.background) } ?? .systemBackground; setNeedsDisplay()
        }
    }
    private lazy var readings = JapaneseFurigana.annotations(for: item.text)
    init(item: ImageTranslationLayout.Item) {
        self.item = item; super.init(frame: .zero)
        isOpaque = false; backgroundColor = .systemBackground
        layer.cornerRadius = 2; clipsToBounds = true; contentMode = .redraw
        isAccessibilityElement = true; accessibilityTraits = .button
        accessibilityLabel = item.text
        accessibilityHint = "查看完整译文并核对原文"
        accessibilityIdentifier = "imageTranslationBlock-\(item.id)"
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ImageTranslationTile, _: UITraitCollection) in view.setNeedsDisplay() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let placement, bounds.width > 0, bounds.height > 0 else { return }
        let color = palette.map { UIColor(rgb: $0.ink) } ?? UIColor.label.resolvedColor(with: traitCollection)
        let annotations = showFurigana ? readings : []
        let fitted = ImageOverlayTypography.fitted(item: item, placement: placement, color: color, annotations: annotations)
        context.saveGState(); context.textMatrix = .identity
        // CoreText draws upwards from the bottom-left corner of the frame's path.
        context.translateBy(x: fitted.rect.minX, y: fitted.rect.maxY); context.scaleBy(x: 1, y: -1)
        CTFrameDraw(fitted.frame, context); context.restoreGState()
        if fitted.truncated {
            let dot = CGRect(x: max(0, bounds.width - 7), y: max(0, bounds.height - 7), width: 7, height: 7)
            (backgroundColor ?? .systemBackground).setFill(); context.fill(dot)
            color.withAlphaComponent(0.6).setFill(); context.fillEllipse(in: dot.insetBy(dx: 2, dy: 2))
        }
    }
}

enum ImageOverlayTypography {
    struct Fitted {
        let frame: CTFrame
        /// Where the frame's path sits, in the tile's own top-left coordinates.
        let rect: CGRect
        let fontSize: CGFloat
        /// Fixed distance between lines; nil keeps CoreText's spacing, which
        /// makes room for furigana.
        let lineHeight: CGFloat?
        let truncated: Bool
    }

    /// - Parameter placement: measured from the tile's own corner (`Placement.local`).
    static func fitted(item: ImageTranslationLayout.Item, placement: ImageTranslationLayout.Placement, color: UIColor,
                       annotations: [JapaneseFurigana.Annotation] = []) -> Fitted {
        let text = placement.text, length = (item.text as NSString).length
        let alignment: NSTextAlignment
        switch placement.alignment { case .leading: alignment = .natural; case .center: alignment = .center; case .trailing: alignment = .right }
        let progression: CFDictionary? = item.vertical
            ? [kCTFrameProgressionAttributeName: CTFrameProgression.rightToLeft.rawValue] as CFDictionary : nil
        func frame(_ fontSize: CGFloat, lineHeight: CGFloat?, size: CGSize) -> CTFrame {
            var reader = ReaderPreferences(); reader.customFontSize = 12; reader.customLineSpacing = 0
            let value = NSMutableAttributedString(attributedString: RubyTextLayout.attributed(item.text, annotations: annotations,
                reader: reader, scale: Double(fontSize / 12), heading: false, semibold: item.heading, alignment: alignment))
            let all = NSRange(location: 0, length: value.length)
            value.addAttribute(.foregroundColor, value: color, range: all)
            if let lineHeight {
                let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment
                paragraph.minimumLineHeight = lineHeight; paragraph.maximumLineHeight = lineHeight
                value.addAttribute(.paragraphStyle, value: paragraph, range: all)
            }
            if item.vertical {
                value.addAttribute(NSAttributedString.Key(kCTVerticalFormsAttributeName as String), value: true, range: all)
            }
            let setter = CTFramesetterCreateWithAttributedString(value)
            return CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), progression)
        }
        func complete(_ frame: CTFrame) -> Bool { CTFrameGetVisibleStringRange(frame).length >= length }
        /// The largest size in `range` that fits, trying the largest first.
        func largest(_ range: ClosedRange<CGFloat>, _ fits: (CGFloat) -> Bool) -> CGFloat? {
            if fits(range.upperBound) { return range.upperBound }
            guard range.lowerBound < range.upperBound, fits(range.lowerBound) else { return nil }
            var low = range.lowerBound, high = range.upperBound
            for _ in 0..<6 { let middle = (low + high) / 2; if fits(middle) { low = middle } else { high = middle } }
            return low
        }
        // Never larger than the source text, so a shorter translation keeps
        // the original size instead of swelling to fill the box.
        let cap = max(1, placement.line * 0.85)

        // Source size and source line positions: one translated line in each
        // source line, so the text sits where the original did.
        if !item.vertical, annotations.isEmpty, placement.single || placement.pitch != nil {
            let rows = placement.single ? 1 : placement.rows
            let pitch = placement.single ? text.height : placement.pitch ?? text.height
            let slots = CGSize(width: text.width, height: pitch * CGFloat(rows) + 1)
            if let size = largest(cap * 0.7...cap, { complete(frame($0, lineHeight: pitch, size: slots)) }) {
                // CoreText centres the glyphs in a fixed line height; centre the
                // first line on the first source line.
                let top = placement.single ? text.minY : text.minY - (pitch - placement.line) / 2
                return .init(frame: frame(size, lineHeight: pitch, size: slots),
                             rect: CGRect(origin: CGPoint(x: text.minX, y: top), size: slots),
                             fontSize: size, lineHeight: pitch, truncated: false)
            }
        }

        // A longer translation: smaller type set close together, centred on a
        // single source line or from the top of a paragraph.
        let area = text.insetBy(dx: -placement.padding / 2, dy: -placement.padding / 2).intersection(placement.tile)
        let natural = item.vertical || !annotations.isEmpty
        func spacing(_ size: CGFloat) -> CGFloat? { natural ? nil : size * 1.2 }
        let smallest = min(8, cap * 0.6)
        let size = largest(smallest...max(smallest, cap)) { complete(frame($0, lineHeight: spacing($0), size: area.size)) } ?? smallest
        let result = frame(size, lineHeight: spacing(size), size: area.size)
        var rect = area
        if placement.single, !item.vertical { rect.origin.y += max(0, (area.height - usedHeight(result, height: area.height)) / 2) }
        return .init(frame: result, rect: rect, fontSize: size, lineHeight: spacing(size), truncated: !complete(result))
    }

    /// From the top of the frame to the bottom of its last line.
    private static func usedHeight(_ frame: CTFrame, height: CGFloat) -> CGFloat {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        guard let last = lines.last else { return 0 }
        var origin = CGPoint.zero, descent: CGFloat = 0
        CTFrameGetLineOrigins(frame, CFRange(location: lines.count - 1, length: 1), &origin)
        _ = CTLineGetTypographicBounds(last, nil, &descent, nil)
        return height - (origin.y - descent)
    }
}

private struct ZoomedTranslationImage: UIViewRepresentable {
    let image: UIImage
    let pixels: ImageOverlayPalette.Pixels?
    let items: [ImageTranslationLayout.Item]
    let original: Bool
    let reader: ReaderPreferences
    let target: String
    let enabled: Bool
    let tapped: (Int) -> Void
    func makeUIView(context: Context) -> TranslationZoomScrollView { TranslationZoomScrollView() }
    func updateUIView(_ view: TranslationZoomScrollView, context: Context) {
        view.ratio = image.size.height / image.size.width
        view.canvas.configure(image: image, pixels: pixels, items: items, original: original, reader: reader, target: target,
                              enabled: enabled, tapped: tapped)
        view.setNeedsLayout()
    }
}

final class TranslationZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let canvas = ImageTranslationCanvasView()
    var ratio: CGFloat = 1
    private var lastWidth: CGFloat = 0
    override init(frame: CGRect) {
        super.init(frame: frame); delegate = self
        minimumZoomScale = 1; maximumZoomScale = 5
        addSubview(canvas)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(resetZoom)); doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        accessibilityIdentifier = "imageTranslationZoom"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, lastWidth != bounds.width else { return }
        lastWidth = bounds.width; setZoomScale(1, animated: false)
        canvas.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.width * ratio)
        contentSize = canvas.bounds.size
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }
    @objc private func resetZoom() { setZoomScale(zoomScale > 1 ? 1 : 2, animated: true) }
}
