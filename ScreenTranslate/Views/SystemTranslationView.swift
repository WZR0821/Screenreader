import SwiftUI
@preconcurrency import Translation

struct SystemTranslationRequest: Identifiable {
    let id: UUID
    let text: String
    let settings: AppSettings
    let started: Date
    let warning: String?
    let recognitionSeconds: TimeInterval?
    var source: Locale.Language? {
        settings.source == .automatic ? nil : Locale.Language(identifier: settings.source.rawValue)
    }
    var target: Locale.Language {
        Locale.Language(identifier: settings.target == .simplifiedChinese ? "zh-Hans" : (settings.target == .japanese ? "ja" : "en"))
    }
}

/// Keep Apple's session anchored to this visible view for its entire lifetime.
struct SystemTranslationView: View {
    let request: SystemTranslationRequest
    let completed: (UUID, Result<String, Error>) -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ProgressView()
                Text("系统翻译中").font(.headline)
                Text("首次使用按提示下载语言。此方式不调用 AI API，不使用自定义提示词或术语表。")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("快速 · 系统翻译").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消", action: cancel) } }
                .translationTask(.init(source: request.source, target: request.target)) { session in
                    do {
                        let response = try await session.translate(request.text)
                        try Task.checkCancellation()
                        await MainActor.run { completed(request.id, .success(response.targetText)) }
                    } catch { await MainActor.run { completed(request.id, .failure(error)) } }
                }
        }.interactiveDismissDisabled()
    }
}
