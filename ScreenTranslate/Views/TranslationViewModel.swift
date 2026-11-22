import Foundation
import Combine
import PhotosUI
import SwiftUI
import ImageIO

@MainActor
final class TranslationViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle, loading, recognizing, translating, understanding, preparing
        var title: String {
            switch self { case .idle: return ""; case .loading: return "正在读取图片";
            case .recognizing: return "正在识别文字"; case .translating: return "正在翻译";
            case .understanding: return "正在理解图片"; case .preparing: return "正在准备图片" }
        }
    }
    @Published var text = "" {
        didSet {
            guard text != oldValue, !busy, !applyingBlockReview else { return }
            textCameFromOCR = false
            recognizedOCR = nil
            reviewedSourceBlocks = nil
            result = nil; error = nil; ocrWarning = nil
        }
    }
    @Published private(set) var preview: UIImage?
    @Published private(set) var phase = Phase.idle {
        didSet {
            if phase != oldValue { phaseStartedAt = Date() }
            if phase == .idle { isTranslating = false; streamingText = "" }
        }
    }
    @Published private(set) var isTranslating = false
    /// Text received so far from a streamed reply. A preview only: it is
    /// cleared when the job ends and replaced by the validated result.
    @Published private(set) var streamingText = ""
    @Published private(set) var phaseStartedAt = Date()
    @Published private(set) var result: TranslationResult?
    @Published var error: String?
    @Published private(set) var imageData: Data?
    @Published private(set) var ocrWarning: String?
    @Published private(set) var startedAt = Date()
    @Published var systemRequest: SystemTranslationRequest?
    private var job: Task<Void, Never>?
    private var jobID = UUID()
    private var textCameFromOCR = false
    private var applyingBlockReview = false
    private var reviewedSourceBlocks: [ReadingBlock]?
    @Published private(set) var recognizedOCR: OCRResult?
    @Published var showReview = false
    @Published var textDirection: OCRTextDirection = .automatic {
        didSet { if textDirection != oldValue { resetRecognition() } }
    }
    private let store: SettingsStore
    var pipeline: TranslationPipeline
    var busy: Bool { phase != .idle }

    init(store: SettingsStore, pipeline: TranslationPipeline = TranslationPipeline()) {
        self.store = store
        self.pipeline = pipeline
    }

    func loadPhoto(_ item: PhotosPickerItem) {
        guard !busy else { return }
        begin(.loading)
        let id = jobID
        job = Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw TranslationError.invalidImage }
                try Task.checkCancellation()
                guard id == jobID else { return }
                try acceptImage(data)
            } catch is CancellationError {} catch { if id == jobID { self.error = error.localizedDescription } }
            if id == jobID { phase = .idle }
        }
    }

    func paste(_ providers: [NSItemProvider]) {
        guard !busy else { return }
        let imagesOnly = store.settings.mode == .visual
        begin(.loading)
        let id = jobID
        job = Task {
            do {
                let content = try await ClipboardInput.load(providers, imagesOnly: imagesOnly)
                try Task.checkCancellation()
                guard id == jobID else { return }
                switch content {
                case .image(let data): try acceptImage(data)
                case .text(let value):
                    imageData = nil; preview = nil; recognizedOCR = nil; textCameFromOCR = false
                    reviewedSourceBlocks = nil
                    ocrWarning = nil; text = value
                }
            } catch is CancellationError {} catch { if id == jobID { self.error = error.localizedDescription } }
            if id == jobID { phase = .idle }
        }
    }

    func acceptImage(_ data: Data) throws {
        guard data.count <= 25 * 1_024 * 1_024 else { throw TranslationError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let h = props[kCGImagePropertyPixelHeight] as? NSNumber,
              w.doubleValue * h.doubleValue <= 100_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 900
              ] as CFDictionary) else { throw TranslationError.invalidImage }
        recognizedOCR = nil; textCameFromOCR = false
        reviewedSourceBlocks = nil
        preview = UIImage(cgImage: image)
        imageData = data
        result = nil
        text = ""
        ocrWarning = nil
        error = nil
    }

    func recognize() {
        guard let data = imageData, !busy else { return }
        reviewedSourceBlocks = nil
        begin(.recognizing)
        let id = jobID
        let snapshot = store.settings
        let direction = textDirection
        job = Task {
            do {
                let recognized = try await pipeline.recognize(data, settings: snapshot, direction: direction, cleanScreenText: false)
                try Task.checkCancellation()
                guard id == jobID else { return }
                text = recognized.text
                textCameFromOCR = true; recognizedOCR = recognized
                ocrWarning = recognized.lowConfidence ? "部分文字可能识别不准确，请核对后翻译。" : nil
                showReview = !recognized.reviewItems.isEmpty
            } catch is CancellationError {} catch { if id == jobID { self.error = error.localizedDescription } }
            if id == jobID { phase = .idle }
        }
    }

    func translate(forceRefresh: Bool = false) {
        guard !busy else { return }
        if store.settings.mode == .visual && imageData == nil {
            error = TranslationError.imageRequired.localizedDescription; return
        }
        if store.settings.mode == .quick && store.settings.quickEngine == .system {
            translateWithSystem(forceRefresh: forceRefresh); return
        }
        let snapshot: (AppSettings, String)
        do {
            if imageData == nil || (store.settings.imageMode != .visual && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                _ = try TextPreparation.validated(text)
            }
            snapshot = try store.credentials()
        } catch { self.error = error.localizedDescription; return }
        let input = text
        let image = imageData
        let direction = textDirection
        let warning = ocrWarning
        let reviewedBlocks = reviewedSourceBlocks
        let visual = image != nil && snapshot.0.imageMode == .visual
        begin(visual ? .preparing : (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .recognizing : .translating), retainingResult: true)
        let id = jobID
        let partial: APIClient.PartialHandler = { text in
            Task { @MainActor in
                // Updates may arrive out of order; never let the preview shrink.
                guard id == self.jobID, self.busy, text.count >= self.streamingText.count else { return }
                self.streamingText = text
            }
        }
        job = Task {
            do {
                var translated: TranslationResult
                let started = Date()
                if visual, let image {
                    translated = try await pipeline.image(image, settings: snapshot.0, key: snapshot.1, direction: direction, progress: { stage in
                        Task { @MainActor in
                            guard id == self.jobID, self.busy else { return }
                            self.phase = stage == .requesting ? .understanding : .preparing
                        }
                    }, onPartial: partial)
                } else if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let image {
                    // Connect to the provider while OCR runs.
                    pipeline.warmUp(snapshot.0)
                    let recognized = try await pipeline.recognize(image, settings: snapshot.0, direction: direction)
                    let recognitionSeconds = Date().timeIntervalSince(started)
                    try Task.checkCancellation()
                    guard id == jobID else { return }
                    text = recognized.text
                    recognizedOCR = recognized
                    textCameFromOCR = true
                    ocrWarning = recognized.lowConfidence ? "部分文字需要复核。" : nil
                    phase = .translating
                    translated = try await pipeline.recognizedText(recognized, settings: snapshot.0, key: snapshot.1,
                        forceRefresh: forceRefresh, onPartial: partial)
                    translated.recognitionSeconds = recognitionSeconds
                    translated.refinementSeconds = recognized.refinementSeconds
                } else if let recognized = recognizedOCR, recognized.text == input {
                    translated = try await pipeline.recognizedText(recognized, settings: snapshot.0, key: snapshot.1,
                        forceRefresh: forceRefresh, onPartial: partial)
                    // This run reused the on-screen OCR. Do not count earlier work again.
                    translated.recognitionSeconds = 0; translated.refinementSeconds = 0
                } else {
                    translated = try await pipeline.text(input, settings: snapshot.0, key: snapshot.1,
                        initialWarning: warning, readingBlocks: reviewedBlocks, forceRefresh: forceRefresh,
                        origin: image == nil ? .keyboard : .external, onPartial: partial)
                }
                try Task.checkCancellation()
                guard id == jobID else { return }
                translated.elapsed = Date().timeIntervalSince(started)
                do { try store.record(translated) }
                catch { translated.warning = [translated.warning, "译文已生成，但翻译记录保存失败。"].compactMap { $0 }.joined(separator: "\n") }
                result = translated
            } catch is CancellationError {} catch { if id == jobID { self.error = error.localizedDescription } }
            if id == jobID { phase = .idle }
        }
    }

    func cancel() {
        job?.cancel()
        jobID = UUID()
        phase = .idle
        systemRequest = nil
        showReview = false
    }

    private func translateWithSystem(forceRefresh: Bool) {
        #if targetEnvironment(simulator)
        error = TranslationError.systemUnavailable.localizedDescription
        return
        #else
        let selected = store.settings
        let input = text
        let image = imageData
        begin(image != nil && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .recognizing : .translating, retainingResult: true)
        let id = jobID
        job = Task {
            do {
                var clean = input
                var warning = ocrWarning
                var recognitionSeconds: TimeInterval?
                if clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let image {
                    let start = Date()
                    let recognized = try await pipeline.recognize(image, settings: selected, direction: textDirection)
                    clean = recognized.text
                    recognizedOCR = recognized; textCameFromOCR = true
                    recognitionSeconds = Date().timeIntervalSince(start)
                    warning = recognized.lowConfidence ? "部分识字不清晰，请核对原文。" : nil
                }
                clean = try TextPreparation.validated(clean)
                try Task.checkCancellation()
                guard id == jobID else { return }
                text = clean; phase = .translating
                // Apple cannot translate a language into itself, so text already
                // in the target language needs the next one in the priority order.
                let resolution = selected.resolvingTarget(for: clean, origin: image == nil ? .keyboard : .external)
                let snapshot = resolution.settings
                let blocks = systemSourceBlocks(for: clean)
                let generation = await pipeline.cache.generationToken()
                let identity = try TranslationCache.key(text: clean, settings: snapshot, apiKey: "",
                    readingBlocks: blocks, fromImageText: false, engine: "AppleTranslation")
                if snapshot.cacheTranslations, !forceRefresh, let hit = await pipeline.cache.value(for: identity) {
                    try Task.checkCancellation()
                    guard id == jobID else { return }
                    finishSystem(id: id, text: clean, translated: hit.text, settings: snapshot,
                        warning: warning, recognitionSeconds: recognitionSeconds, usedCache: true, blocks: hit.blocks,
                        targetNote: resolution.note)
                    return
                }
                // Apple rejects a language translated into itself. Respect an
                // explicitly selected identical pair without calling any service.
                if snapshot.source.targetLanguage == snapshot.target {
                    finishSystem(id: id, text: clean, translated: clean, settings: snapshot,
                                 warning: warning, recognitionSeconds: recognitionSeconds, cacheGeneration: generation,
                                 blocks: blocks?.map { source in var block = source; block.original = source.text; return block },
                                 targetNote: resolution.note)
                } else {
                    systemRequest = .init(id: id, text: clean, settings: snapshot, started: startedAt,
                                          warning: warning, recognitionSeconds: recognitionSeconds, cacheGeneration: generation,
                                          readingBlocks: blocks, targetNote: resolution.note)
                }
            } catch is CancellationError {} catch {
                if id == jobID { self.error = error.localizedDescription; phase = .idle }
            }
        }
        #endif
    }

    func completeSystem(_ id: UUID, outcome: Result<SystemTranslationOutput, Error>) {
        guard let request = systemRequest, id == jobID, id == request.id else { return }
        switch outcome {
        case .success(let translated):
            finishSystem(id: id, text: request.text, translated: translated.text, settings: request.settings,
                         warning: request.warning, recognitionSeconds: request.recognitionSeconds,
                         preparationSeconds: translated.preparationSeconds, translationSeconds: translated.translationSeconds,
                         cacheGeneration: request.cacheGeneration, blocks: translated.blocks,
                         targetNote: request.targetNote)
        case .failure(let failure):
            systemRequest = nil; phase = .idle
            error = failure is CancellationError ? "系统翻译已取消，可以重试。"
                : "系统翻译未完成：\(failure.localizedDescription)。请重试或切换 AI 翻译。"
        }
    }

    private func finishSystem(id: UUID, text: String, translated: String, settings: AppSettings,
                              warning: String?, recognitionSeconds: TimeInterval?, usedCache: Bool = false,
                              preparationSeconds: TimeInterval = 0, translationSeconds: TimeInterval = 0, cacheGeneration: Int = 0,
                              blocks: [ReadingBlock]? = nil, targetNote: String? = nil) {
        guard id == jobID else { return }
        var value = TranslationResult(original: text, translated: TranslationFormatting.normalized(translated),
            sourceLanguages: settings.source == .automatic ? LanguageDetector.describe(text) : settings.source.title,
            target: settings.target.title, engine: "系统翻译", elapsed: Date().timeIntervalSince(startedAt), warning: warning)
        guard !value.translated.isEmpty else {
            systemRequest = nil; phase = .idle; error = TranslationError.emptyResponse.localizedDescription; return
        }
        value.mode = .quick; value.recognitionSeconds = recognitionSeconds
        value.blocks = blocks
        value.refinementSeconds = recognitionSeconds == nil ? nil : recognizedOCR?.refinementSeconds
        value.uncertainOCR = recognizedOCR?.lowConfidence
        value.usedCache = usedCache
        value.targetNote = targetNote
        value.preparationSeconds = preparationSeconds; value.requestSeconds = translationSeconds
        if settings.cacheTranslations, !usedCache,
           let identity = try? TranslationCache.key(text: text, settings: settings, apiKey: "",
                readingBlocks: systemSourceBlocks(for: text), fromImageText: false, engine: "AppleTranslation") {
            let output = TranslationOutput(text: value.translated, warning: nil, blocks: blocks)
            Task { await pipeline.cache.insert(output, for: identity, generation: cacheGeneration) }
        }
        do { try store.record(value) } catch { value.warning = "译文已生成，但翻译记录保存失败。" }
        result = value; systemRequest = nil; phase = .idle
    }

    private func systemSourceBlocks(for text: String) -> [ReadingBlock]? {
        if let reviewedSourceBlocks, !reviewedSourceBlocks.isEmpty { return reviewedSourceBlocks }
        guard let recognizedOCR, recognizedOCR.text == text, !recognizedOCR.blocks.isEmpty else { return nil }
        return recognizedOCR.blocks
    }

    /// What the main button would translate the current text into. The page
    /// shows it before the request is sent, so a changed target is expected.
    /// 识图 reads the picture only once it is sent: the page shows the saved
    /// target, and the result says if the text in the picture changed it.
    func targetResolution(_ settings: AppSettings) -> TargetResolution {
        guard settings.mode != .visual else { return TargetResolution(settings: settings, requested: settings.target) }
        return settings.resolvingTarget(for: text, origin: imageData == nil ? .keyboard : .external)
    }

    func clear() {
        cancel()
        recognizedOCR = nil; textCameFromOCR = false
        reviewedSourceBlocks = nil
        text = ""; imageData = nil; preview = nil; result = nil; error = nil; ocrWarning = nil
    }

    func invalidateTranslation() {
        cancel()
        result = nil; error = nil
    }

    /// 原图直译 was turned on after a quick translation that went out as plain
    /// text. That result has no positions to place on the screenshot, but the
    /// on-screen OCR still has them, so the main button translates again
    /// instead of reopening the result. A block request always comes back
    /// with blocks, so this cannot repeat once it has run.
    func needsImageTranslation(_ settings: AppSettings) -> Bool {
        guard settings.imageOverlay, settings.imageMode != .visual, !busy, imageData != nil,
              let result, result.mode == .quick, result.imageMode == .text, result.blocks == nil,
              let recognizedOCR, !recognizedOCR.blocks.isEmpty, recognizedOCR.text == text else { return false }
        return true
    }

    func requestReview() {
        if let recognizedOCR, !recognizedOCR.reviewItems.isEmpty { showReview = true }
        else { recognize() }
    }

    func applyReview(_ corrections: [Int: String]) {
        guard !busy, let recognizedOCR else { return }
        let reviewed = recognizedOCR.reviewing(corrections)
        text = reviewed.text
        self.recognizedOCR = reviewed; textCameFromOCR = true
        reviewedSourceBlocks = nil
        result = nil
        ocrWarning = reviewed.lowConfidence ? "仍有不确定文字，请继续核对。" : nil
    }

    func resetRecognition() {
        let shouldRecognizeAgain = imageData != nil && textCameFromOCR
        invalidateTranslation()
        recognizedOCR = nil
        reviewedSourceBlocks = nil
        if shouldRecognizeAgain { text = ""; textCameFromOCR = false; ocrWarning = nil }
    }

    func modeChanged() {
        // A mode switch should not undo text the user has already corrected.
        if reviewedSourceBlocks != nil { invalidateTranslation() }
        else { resetRecognition() }
    }

    func applyBlockReview(_ updated: TranslationResult, expected: TranslationResult) throws {
        guard !busy, result == expected, updated.id == expected.id else { throw TranslationError.reviewConflict }
        var updated = updated
        do { try store.replaceRecordedResult(expected, with: updated) }
        catch { updated.warning = [updated.warning, "本段已重译，但翻译记录更新失败。"].compactMap { $0 }.joined(separator: "\n") }
        installReviewedResult(updated)
    }

    func refreshReviewedResult() {
        guard !busy, let current = result,
              let saved = store.history.first(where: { $0.id == current.id }), saved != current,
              saved.blocks?.contains(where: { $0.reviewEngine != nil }) == true else { return }
        installReviewedResult(saved)
    }

    private func installReviewedResult(_ updated: TranslationResult) {
        applyingBlockReview = true
        text = updated.original
        applyingBlockReview = false
        reviewedSourceBlocks = TranslationReview.sourceBlocks(in: updated)
        // Flat OCR lines no longer describe the edited source. Keep the corrected
        // blocks as the source of the next request, including their image bounds.
        recognizedOCR = nil
        // Preserve provenance: an attached image does not make manually typed
        // source text OCR. Language changes must not erase those corrections.
        result = updated
        error = nil
    }

    private func begin(_ stage: Phase, retainingResult: Bool = false) {
        cancel()
        error = nil
        if !retainingResult { result = nil }
        startedAt = Date()
        isTranslating = retainingResult
        phase = stage
    }
}
