import SwiftUI

/// A provider's mark: a letter or symbol on the provider's colour. No
/// third-party logos are bundled.
struct ProviderIcon: View {
    var provider: AIProvider
    /// The user's own name for a custom service; its first character becomes the mark.
    var name: String? = nil
    var size: CGFloat = 34

    private var customInitial: String? {
        guard provider == .custom, let first = name?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        return String(first).uppercased()
    }

    var body: some View {
        // The mark is an overlay: a list draws its row separator from the first
        // text in the row, and that should be the provider's name, not this letter.
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(provider.tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Group {
                    if let letter = customInitial ?? provider.monogram {
                        Text(letter).font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: provider.symbol).font(.system(size: size * 0.44, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

extension AIProvider {
    fileprivate var monogram: String? {
        switch self {
        case .claude: return "C"; case .openAI: return "G"; case .deepSeek: return "D"
        case .qwen: return "通"; case .doubao: return "豆"; case .kimi: return "K"
        case .zhipu: return "智"; case .minimax: return "M"
        case .gemini, .custom: return nil
        }
    }
    fileprivate var symbol: String { self == .gemini ? "sparkle" : "server.rack" }
    fileprivate var tint: Color {
        let hex: Int
        switch self {
        case .claude: hex = 0xC96442; case .openAI: hex = 0x0E8F6F; case .deepSeek: hex = 0x4D6BFE
        case .qwen: hex = 0x6A4DF4; case .doubao: hex = 0x1F7AE0; case .kimi: hex = 0x2B2B33
        case .zhipu: hex = 0x2F54EB; case .minimax: hex = 0xD9365E; case .gemini: hex = 0x3B7DED
        case .custom: hex = 0x6E7380
        }
        return Color(uiColor: UIColor(rgb: .hex(hex)))
    }
}

/// A small capsule label such as 推荐 or 正在用.
struct TagLabel: View {
    @Environment(\.appTheme) private var theme
    var text: String
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(theme.accent)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(theme.accent.opacity(0.14), in: Capsule())
            .fixedSize()
    }
}

/// Icon, name and one line of detail: the row used for providers.
struct ProviderRowLabel: View {
    var provider: AIProvider
    var name: String?
    var title: String
    var detail: String
    var detailColor: Color = .secondary
    var tag: String? = nil
    var iconSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 13) {
            ProviderIcon(provider: provider, name: name, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(title).foregroundStyle(Color.primary).lineLimit(1)
                    if let tag { TagLabel(text: tag) }
                }
                Text(detail).font(.footnote).foregroundStyle(detailColor).lineLimit(2)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A model id with one line of detail under it.
struct ModelLabel: View {
    var id: String
    var detail: String?
    var dimmed = false
    var tag: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Text(id).foregroundStyle(dimmed ? Color.secondary : Color.primary).lineLimit(1)
                if let tag { TagLabel(text: tag) }
            }
            if let detail { Text(detail).font(.footnote).foregroundStyle(Color.secondary).lineLimit(1) }
        }
        .padding(.vertical, ListMetrics.twoLinePadding)
    }
}

/// A row that shows a saved value and opens its editor.
struct ValueRow: View {
    var title: String
    var value: String
    var warn = false

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Color.primary)
            Spacer()
            Text(value).lineLimit(1).foregroundStyle(warn ? Color.orange : Color.secondary)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel)).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

/// A row that folds the rows after it. Unlike `DisclosureGroup` it does not
/// indent them.
struct DisclosureRow: View {
    var title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button { withAnimation { isExpanded.toggle() } } label: {
            HStack {
                Text(title).foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90)).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
        .accessibilityIdentifier("disclosure-" + title)
    }
}

/// A row that opens a web page outside the app.
struct ExternalLinkRow: View {
    var title: String
    var url: URL

    var body: some View {
        Link(destination: url) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel)).accessibilityHidden(true)
            }
        }
    }
}

/// The header card of a provider or model page.
struct ProviderHeader: View {
    var provider: AIProvider
    var name: String?
    var caption: String? = nil
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 15) {
            ProviderIcon(provider: provider, name: name, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                if let caption { Text(caption).font(.footnote).foregroundStyle(.secondary) }
                Text(title).font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.7)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Error and notice shown above a settings list.
struct SettingsFeedback: View {
    @Environment(\.appTheme) private var theme
    var error: String?
    var notice: String?

    var body: some View {
        if error != nil || notice != nil {
            VStack(spacing: 8) {
                if let error { ErrorBanner(message: error) }
                if let notice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.vertical, 6)
                        .accessibilityIdentifier("settingsNotice")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 6).background(Theme.background)
        }
    }
}

/// An API key field with a show/hide button.
struct APIKeyField: View {
    @Binding var key: String
    @State private var reveal = false
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack {
            Group {
                if reveal { TextField("API Key", text: $key) } else { SecureField("API Key", text: $key) }
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled().focused(focus)
            .accessibilityIdentifier("apiKeyField")
            Button { reveal.toggle() } label: {
                Image(systemName: reveal ? "eye.slash" : "eye").frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless).accessibilityLabel(reveal ? "隐藏密钥" : "显示密钥")
        }
        .onDisappear { reveal = false }
    }
}

/// Sends one short sentence through a model without touching saved settings.
enum ConnectionCheck {
    @MainActor
    static func run(settings: AppSettings, entryID: String, configuration: ProviderConfiguration,
                    apiKey: String) async throws -> TimeInterval {
        var snapshot = settings
        snapshot.activeID = entryID
        snapshot.configurations[entryID] = configuration
        snapshot.mode = .quick; snapshot.source = .english; snapshot.target = .simplifiedChinese
        snapshot.glossary = ""; snapshot.customPrompt = ""
        let started = Date()
        _ = try await TranslationPipeline().client.translate("Hello.", settings: snapshot, apiKey: apiKey, timeout: 15)
        try Task.checkCancellation()
        return Date().timeIntervalSince(started)
    }
}
