import Foundation

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" } }
}

enum AccentTheme: String, Codable, CaseIterable, Identifiable {
    case graphite, blue, terracotta, olive, rose, custom
    var id: String { rawValue }
    var title: String {
        switch self { case .graphite: return "石墨"; case .blue: return "海蓝"; case .terracotta: return "陶土";
        case .olive: return "橄榄"; case .rose: return "莓红"; case .custom: return "自定义" }
    }
    var color: ThemeRGB {
        switch self { case .graphite: return .hex(0x343432); case .blue: return .hex(0x007AFF)
        case .terracotta: return .hex(0x975439); case .olive: return .hex(0x596645)
        case .rose: return .hex(0x944E64); case .custom: return .hex(0x28465E) }
    }
}

struct ThemeRGB: Codable, Equatable {
    var red: Double; var green: Double; var blue: Double
    static func hex(_ value: Int) -> Self {
        .init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    var normalized: Self {
        func clamp(_ v: Double) -> Double { v.isFinite ? min(1, max(0, v)) : 0 }
        return .init(red: clamp(red), green: clamp(green), blue: clamp(blue))
    }
    var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        let rgb = normalized
        return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }
    func contrast(with other: Self) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
    func accessible(on background: Self) -> Self {
        var value = normalized
        let endpoint = background.luminance > 0.5 ? 0.0 : 1.0
        for _ in 0..<50 where value.contrast(with: background) < 4.8 {
            value = .init(red: value.red * 0.92 + endpoint * 0.08,
                          green: value.green * 0.92 + endpoint * 0.08,
                          blue: value.blue * 0.92 + endpoint * 0.08)
        }
        return value
    }
    var foreground: Self { contrast(with: .hex(0xffffff)) >= contrast(with: .hex(0)) ? .hex(0xffffff) : .hex(0) }
}

enum ReaderTextSize: String, Codable, CaseIterable, Identifiable {
    case small, regular, large
    var id: String { rawValue }
    var title: String { switch self { case .small: return "较小"; case .regular: return "标准"; case .large: return "较大" } }
    var points: Double { switch self { case .small: return 15; case .regular: return 17; case .large: return 20 } }
}

enum ReaderSpacing: String, Codable, CaseIterable, Identifiable {
    case compact, standard, relaxed
    var id: String { rawValue }
    var title: String { switch self { case .compact: return "紧凑"; case .standard: return "标准"; case .relaxed: return "宽松" } }
    var paragraph: Double { switch self { case .compact: return 8; case .standard: return 14; case .relaxed: return 24 } }
    var line: Double { switch self { case .compact: return 2; case .standard: return 5; case .relaxed: return 9 } }
    var htmlLineHeight: Double { switch self { case .compact: return 1.4; case .standard: return 1.55; case .relaxed: return 1.9 } }
}

enum ReaderFont: String, Codable, CaseIterable, Identifiable {
    case system, serif, rounded
    var id: String { rawValue }
    var title: String { switch self { case .system: return "系统字体"; case .serif: return "衬线字体"; case .rounded: return "圆角字体" } }
    var cssFamily: String {
        switch self {
        case .system: return "-apple-system,BlinkMacSystemFont,\"Hiragino Sans\",\"PingFang SC\",sans-serif"
        case .serif: return "ui-serif,\"New York\",\"Hiragino Mincho ProN\",\"Songti SC\",serif"
        case .rounded: return "ui-rounded,\"SF Pro Rounded\",-apple-system,\"Hiragino Sans\",\"PingFang SC\",sans-serif"
        }
    }
}

struct ReaderPreferences: Codable, Equatable {
    var textSize: ReaderTextSize = .regular
    var spacing: ReaderSpacing = .standard
    var showOriginal = false
    var showJapaneseFurigana = false
    var font: ReaderFont = .system
    var emphasized = false
    var customFontSize: Double?
    var customLineSpacing: Double?
    var customParagraphSpacing: Double?

    static let fontSizeRange = 12.0...30.0
    static let lineSpacingRange = 0.0...20.0
    static let paragraphSpacingRange = 0.0...36.0

    var fontSize: Double { Self.bounded(customFontSize, in: Self.fontSizeRange) ?? textSize.points }
    var lineSpacing: Double { Self.bounded(customLineSpacing, in: Self.lineSpacingRange) ?? spacing.line }
    var paragraphSpacing: Double { Self.bounded(customParagraphSpacing, in: Self.paragraphSpacingRange) ?? spacing.paragraph }
    // Keep existing presets unchanged; custom spacing is extra space between lines,
    // on top of the font's approximate natural line height.
    var htmlLineHeight: Double { customLineSpacing == nil ? spacing.htmlLineHeight : 1.3 + lineSpacing / fontSize }

    init(textSize: ReaderTextSize = .regular, spacing: ReaderSpacing = .standard, showOriginal: Bool = false,
         font: ReaderFont = .system, emphasized: Bool = false, customFontSize: Double? = nil,
         customLineSpacing: Double? = nil, customParagraphSpacing: Double? = nil, showJapaneseFurigana: Bool = false) {
        self.textSize = textSize; self.spacing = spacing; self.showOriginal = showOriginal
        self.font = font; self.emphasized = emphasized; self.customFontSize = customFontSize
        self.customLineSpacing = customLineSpacing; self.customParagraphSpacing = customParagraphSpacing
        self.showJapaneseFurigana = showJapaneseFurigana
        normalize()
    }

    mutating func normalize() {
        customFontSize = Self.bounded(customFontSize, in: Self.fontSizeRange)
        customLineSpacing = Self.bounded(customLineSpacing, in: Self.lineSpacingRange)
        customParagraphSpacing = Self.bounded(customParagraphSpacing, in: Self.paragraphSpacingRange)
    }

    private static func bounded(_ value: Double?, in range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private enum CodingKeys: String, CodingKey {
        case textSize, spacing, showOriginal, font, emphasized, customFontSize, customLineSpacing, customParagraphSpacing, showJapaneseFurigana
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        textSize = (try values.decodeIfPresent(String.self, forKey: .textSize)).flatMap(ReaderTextSize.init(rawValue:)) ?? .regular
        spacing = (try values.decodeIfPresent(String.self, forKey: .spacing)).flatMap(ReaderSpacing.init(rawValue:)) ?? .standard
        showOriginal = try values.decodeIfPresent(Bool.self, forKey: .showOriginal) ?? false
        showJapaneseFurigana = try values.decodeIfPresent(Bool.self, forKey: .showJapaneseFurigana) ?? false
        font = (try values.decodeIfPresent(String.self, forKey: .font)).flatMap(ReaderFont.init(rawValue:)) ?? .system
        emphasized = try values.decodeIfPresent(Bool.self, forKey: .emphasized) ?? false
        customFontSize = try values.decodeIfPresent(Double.self, forKey: .customFontSize)
        customLineSpacing = try values.decodeIfPresent(Double.self, forKey: .customLineSpacing)
        customParagraphSpacing = try values.decodeIfPresent(Double.self, forKey: .customParagraphSpacing)
        normalize()
    }
}
