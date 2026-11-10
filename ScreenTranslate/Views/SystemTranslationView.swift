import SwiftUI
@preconcurrency import Translation

struct SystemTranslationRequest: Identifiable {
    let id: UUID
    let text: String
    let settings: AppSettings
    let started: Date
    let warning: String?
    let recognitionSeconds: TimeInterval?
    var cacheGeneration: Int = 0
    var readingBlocks: [ReadingBlock]? = nil
    var source: Locale.Language? {
        settings.source == .automatic ? nil : Locale.Language(identifier: settings.source.rawValue)
    }
    var target: Locale.Language {
        Locale.Language(identifier: settings.target.languageCode)
    }
}

struct SystemTranslationOutput {
    var text: String
    var preparationSeconds: TimeInterval
    var translationSeconds: TimeInterval
    var blocks: [ReadingBlock]? = nil
}

/// Keep Apple's session anchored to this visible view for its entire lifetime.
struct SystemTranslationView: View {
    let request: SystemTranslationRequest
    let completed: (UUID, Result<SystemTranslationOutput, Error>) -> Void
    let cancel: () -> Void
    @State private var stage = "检查本机语言包"
    @State private var completedParts = 0
    @State private var totalParts = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 16) {
                ProgressView()
                Text(stage).font(.headline)
                if totalParts > 1 { Text("已完成 \(completedParts) / \(totalParts) 段").font(.caption).monospacedDigit() }
                Text("首次使用请按系统提示准备语言包。翻译完成后自动显示译文。")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(28).frame(maxWidth: .infinity)
            }.background(Theme.background)
                .navigationTitle("快速 · 系统翻译").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消", action: cancel) } }
                .translationTask(.init(source: request.source, target: request.target)) { session in
                    do {
                        let started = ProcessInfo.processInfo.systemUptime
                        let availability = LanguageAvailability()
                        let status: LanguageAvailability.Status
                        if let source = request.source { status = await availability.status(from: source, to: request.target) }
                        else { status = try await availability.status(for: request.text, to: request.target) }
                        guard status != .unsupported else { throw TranslationError.systemLanguageUnsupported }
                        if status == .supported {
                            stage = "按系统提示准备语言包"
                            // An automatic source is resolved by translate(), not prepareTranslation().
                            if request.source != nil { try await session.prepareTranslation() }
                        }
                        try Task.checkCancellation()
                        let ready = ProcessInfo.processInfo.systemUptime
                        stage = status == .supported && request.source == nil ? "准备语言并翻译" : "正在本机翻译"
                        let plan = LocalTranslationPlan(request.text)
                        let imagePlan = request.readingBlocks.map(LocalImageTranslationPlan.init)
                        let requests = imagePlan?.requests ?? plan.requests
                        let batch = requests.map {
                            TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.index))
                        }
                        let requestedIDs = Set(requests.map(\.index))
                        totalParts = imagePlan == nil ? plan.totalParts : requests.count
                        var responses: [Int: String] = [:]
                        for try await response in session.translate(batch: batch) {
                            try Task.checkCancellation()
                            guard let rawID = response.clientIdentifier, let index = Int(rawID),
                                  requestedIDs.contains(index), responses[index] == nil else {
                                throw TranslationError.incompleteSystemTranslation
                            }
                            responses[index] = response.targetText
                            completedParts = imagePlan == nil ? plan.completedParts(responseIDs: Set(responses.keys)) : responses.count
                        }
                        let blocks = try imagePlan?.restored(responses)
                        let text = try blocks?.map(\.text).joined(separator: "\n\n") ?? plan.restored(responses)
                        try Task.checkCancellation()
                        let output = SystemTranslationOutput(text: text, preparationSeconds: ready - started,
                            translationSeconds: ProcessInfo.processInfo.systemUptime - ready, blocks: blocks)
                        await MainActor.run { completed(request.id, .success(output)) }
                    } catch { await MainActor.run { completed(request.id, .failure(error)) } }
                }
        }.interactiveDismissDisabled()
            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
}
