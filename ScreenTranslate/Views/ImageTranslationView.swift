import SwiftUI
import CoreText

struct ImageTranslationView: View {
    let data: Data
    let result: TranslationResult
    var isWorking: Bool
    let review: (Int) -> Void
    @Environment(\.appTheme) private var theme
    @State private var image: UIImage?
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
                ImageTranslationCanvas(image: image, items: ImageTranslationLayout.items(in: result),
                    original: showsOriginal, reader: theme.settings.reader, target: result.target,
                    enabled: !isWorking, tapped: review)
                    .aspectRatio(image.size, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06)))
                    .accessibilityIdentifier("imageTranslationCanvas")
                    .accessibilityHidden(expanded)
            } else if failed {
                ContentUnavailableView("原图暂时无法显示", systemImage: "photo", description: Text("可切换到阅读查看完整译文。"))
            } else {
                ProgressView("正在准备原图").frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task(id: data) {
            image = nil; failed = false
            let prepared = await Task.detached(priority: .userInitiated) { SourceImagePresentation.prepare(data) }.value
            guard !Task.isCancelled else { return }
            image = prepared.flatMap { UIImage(data: $0.data) }; failed = image == nil
        }
        .fullScreenCover(isPresented: $expanded, onDismiss: {
            if let id = pendingReview { pendingReview = nil; review(id) }
        }) {
            if let image {
                NavigationStack {
                    ZoomedTranslationImage(image: image, items: ImageTranslationLayout.items(in: result),
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
    let items: [ImageTranslationLayout.Item]
    let original: Bool
    let reader: ReaderPreferences
    let target: String
    let enabled: Bool
    let tapped: (Int) -> Void
    func makeUIView(context: Context) -> ImageTranslationCanvasView { ImageTranslationCanvasView() }
    func updateUIView(_ view: ImageTranslationCanvasView, context: Context) {
        view.configure(image: image, items: items, original: original, reader: reader, target: target, enabled: enabled, tapped: tapped)
    }
}

final class ImageTranslationCanvasView: UIView {
    private let photo = UIImageView()
    private var tiles: [ImageTranslationTile] = []
    private var items: [ImageTranslationLayout.Item] = []
    private var tapped: ((Int) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(photo); clipsToBounds = true
        photo.contentMode = .scaleToFill; photo.isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(image: UIImage, items: [ImageTranslationLayout.Item], original: Bool,
                   reader: ReaderPreferences, target: String, enabled: Bool, tapped: @escaping (Int) -> Void) {
        photo.image = image; self.tapped = tapped
        let visibleItems = original ? [] : items
        if self.items != visibleItems {
            tiles.forEach { $0.isHidden = true; $0.removeFromSuperview() }
            self.items = visibleItems
            tiles = visibleItems.map { item in
                let tile = ImageTranslationTile(item: item)
                tile.addTarget(self, action: #selector(selectTile(_:)), for: .touchUpInside)
                addSubview(tile); return tile
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
            let box = tile.item.box
            let source = CGRect(x: box.x * bounds.width, y: (1 - box.y - box.height) * bounds.height,
                                width: box.width * bounds.width, height: box.height * bounds.height)
            // Vision bounds hug glyph ink, not font line height. A small margin
            // covers antialiased edges and gives short single-line labels room.
            tile.frame = source.insetBy(dx: -2, dy: -2).intersection(bounds)
        }
    }
    @objc private func selectTile(_ tile: ImageTranslationTile) { tapped?(tile.item.blockID) }
}

final class ImageTranslationTile: UIControl {
    let item: ImageTranslationLayout.Item
    var showFurigana = false { didSet { if oldValue != showFurigana { setNeedsDisplay() } } }
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
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }
        let area = bounds.insetBy(dx: min(1, bounds.width * 0.03), dy: min(0.5, bounds.height * 0.02))
        let color = UIColor.label.resolvedColor(with: traitCollection)
        let annotations = showFurigana ? readings : []
        let fitted = ImageOverlayTypography.fitted(item: item, size: area.size, color: color, annotations: annotations)
        context.saveGState(); context.textMatrix = .identity
        context.translateBy(x: area.minX, y: bounds.height - area.minY); context.scaleBy(x: 1, y: -1)
        CTFrameDraw(fitted.frame, context); context.restoreGState()
        if fitted.truncated {
            let dot = CGRect(x: max(0, bounds.width - 7), y: max(0, bounds.height - 7), width: 7, height: 7)
            UIColor.systemBackground.setFill(); context.fill(dot)
            UIColor.secondaryLabel.setFill(); context.fillEllipse(in: dot.insetBy(dx: 2, dy: 2))
        }
    }
}

enum ImageOverlayTypography {
    struct Fitted { let frame: CTFrame; let fontSize: CGFloat; let truncated: Bool }
    static func fitted(item: ImageTranslationLayout.Item, size: CGSize, color: UIColor,
                       annotations: [JapaneseFurigana.Annotation] = []) -> Fitted {
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        let attributes: CFDictionary? = item.vertical
            ? [kCTFrameProgressionAttributeName: CTFrameProgression.rightToLeft.rawValue] as CFDictionary : nil
        func frame(_ fontSize: CGFloat) -> CTFrame {
            var reader = ReaderPreferences(); reader.customFontSize = 12; reader.customLineSpacing = 0
            let value = NSMutableAttributedString(attributedString: RubyTextLayout.attributed(item.text,
                annotations: annotations, reader: reader, scale: Double(fontSize / 12), heading: false, semibold: item.heading))
            value.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: value.length))
            if item.vertical {
                value.addAttribute(NSAttributedString.Key(kCTVerticalFormsAttributeName as String), value: true,
                                   range: NSRange(location: 0, length: value.length))
            }
            let setter = CTFramesetterCreateWithAttributedString(value)
            return CTFramesetterCreateFrame(setter, CFRange(), path, attributes)
        }
        let length = (item.text as NSString).length
        // Never grow beyond the source region; a dot signals overflow and tapping
        // always exposes the complete text. Zoom scales both pixels and glyphs.
        let maximum = min(28, max(8, (item.vertical ? size.width : size.height) * 0.82))
        var low: CGFloat = 8, high = maximum
        for _ in 0..<7 {
            let middle = (low + high) / 2
            if CTFrameGetVisibleStringRange(frame(middle)).length >= length { low = middle } else { high = middle }
        }
        let result = frame(low)
        return .init(frame: result, fontSize: low, truncated: CTFrameGetVisibleStringRange(result).length < length)
    }
}

private struct ZoomedTranslationImage: UIViewRepresentable {
    let image: UIImage
    let items: [ImageTranslationLayout.Item]
    let original: Bool
    let reader: ReaderPreferences
    let target: String
    let enabled: Bool
    let tapped: (Int) -> Void
    func makeUIView(context: Context) -> TranslationZoomScrollView { TranslationZoomScrollView() }
    func updateUIView(_ view: TranslationZoomScrollView, context: Context) {
        view.ratio = image.size.height / image.size.width
        view.canvas.configure(image: image, items: items, original: original, reader: reader, target: target, enabled: enabled, tapped: tapped)
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
