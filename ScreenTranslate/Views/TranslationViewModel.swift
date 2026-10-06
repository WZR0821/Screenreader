import Foundation
import Combine
import PhotosUI
import SwiftUI
import ImageIO

@MainActor
final class TranslationViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle, loading, recognizing, translating, understanding
        var title: String {
            switch self { case .idle: return ""; case .loading: return "正在读取图片";
            case .recognizing: return "正在识别文字"; case .translating: return "正在翻译";
            case .understanding: return "正在理解图片" }
        }
    }
    @Published var text = "" {
        didSet {
            guard text != oldValue, !busy else { return }
            textCameFromOCR = false
            recognizedOCR = nil
            result = nil; error = nil; ocrWarning = nil
        }
    }
    @Published private(set) var preview: UIImage?
    @Published private(set) var phase = Phase.idle
    @Published private(set) var result: TranslationResult?
    @Published var error: String?
    @Published private(set) var imageData: Data?
    @Published private(set) var ocrWarning: String?
    @Published private(set) var startedAt = Date()
    @Published var systemRequest: SystemTranslationRequest?
    private var job: Task<Void, Never>?
    private var jobID = UUID()
    private var textCameFromOCR = false
    private var recognizedOCR: OCRResult?
    private let store: SettingsStore
    var pipeline: TranslationPipeline
    var busy: Bool { phase != .idle }

    init(store: SettingsStore, pipeline: TranslationPipeline = TranslationPipeline()) {
        self.store = store
        self.pipeline = pipeline
    }

    func loadPhoto(_ item: PhotosPickerItem) {
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

    func loadFile(_ url: URL) {
        begin(.loading)
        let id = jobID
        job = Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let permitted = url.startAccessingSecurityScopedResource()
                    defer { if permitted { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 25 * 1_024 * 1_024 else { throw TranslationError.imageTooLarge }
                    return try Data(contentsOf: url, options: .mappedIfSafe)
                }.value
                try Task.checkCancellation()
                guard id == jobID else { return }
                try acceptImage(data)
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
        preview = UIImage(cgImage: image)
        imageData = data
        result = nil
        text = ""
        ocrWarning = nil
        error = nil
    }

    func recognize() {
        guard let data = imageData, !busy else { return }
        begin(.recognizing)
        let id = jobID
        let source = store.settings.source
        let words = TextPreparation.recognitionWords(glossary: store.settings.glossary)
        let mode = store.settings.mode
        job = Task {
            do {
                let recognized = try await pipeline.ocr.recognize(data, source: source, customWords: words, cleanScreenText: false, mode: mode)
                try Task.checkCancellation()
                guard id == jobID else { return }
                text = recognized.text
                textCameFromOCR = true; recognizedOCR = recognized
                ocrWarning = recognized.lowConfidence ? "部分文字可能识别不准确，请核对后翻译。" : nil
            } catch is CancellationError {} catch { if id == jobID { self.error = error.localizedDescription } }
            if id == jobID { phase = .idle }
        }
    }

    func translate() {
        guard !busy else { return }
        if store.settings.mode == .visual && imageData == nil {
            error = TranslationError.imageRequired.localizedDescription; return
        }
        if store.settings.mode == .quick && store.settings.quickEngine == .system {
            translateWithSystem(); return
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
        let warning = ocrWarning
        let visual = image != nil && snapshot.0.imageMode == .visual
        begin(visual ? .understanding : (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .recognizing : .translating))
        let id = jobID
        job = Task {
            do {
                var translated: TranslationResult
                let started = Date()
                if visual, let image {
                    translated = try await pipeline.image(image, settings: snapshot.0, key: snapshot.1)
                } else if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let image {
                    let recognized = try await pipeline.ocr.recognize(image, source: snapshot.0.source,
                        customWords: TextPreparation.recognitionWords(glossary: snapshot.0.glossary), cleanScreenText: snapshot.0.cleanScreenText,
                        mode: snapshot.0.mode)
                    let recognitionSeconds = Date().timeIntervalSince(started)
                    try Task.checkCancellation()
                    guard id == jobID else { return }
                    text = recognized.text
                    recognizedOCR = recognized
                    textCameFromOCR = true
                    phase = .translating
                    translated = try await pipeline.recognizedText(recognized, settings: snapshot.0, key: snapshot.1)
                    translated.recognitionSeconds = recognitionSeconds
                } else if let recognized = recognizedOCR, recognized.text == input {
                    translated = try await pipeline.recognizedText(recognized, settings: snapshot.0, key: snapshot.1)
                } else {
                    translated = try await pipeline.text(input, settings: snapshot.0, key: snapshot.1,
                                                        initialWarning: warning)
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
    }

    private func translateWithSystem() {
        #if targetEnvironment(simulator)
        error = TranslationError.systemUnavailable.localizedDescription
        return
        #else
        let snapshot = store.settings
        let input = text
        let image = imageData
        begin(image != nil && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .recognizing : .translating)
        let id = jobID
        job = Task {
            do {
                var clean = input
                var warning = ocrWarning
                var recognitionSeconds: TimeInterval?
                if clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let image {
                    let start = Date()
                    let recognized = try await pipeline.ocr.recognize(image, source: snapshot.source,
                        cleanScreenText: snapshot.cleanScreenText, mode: .quick)
                    clean = recognized.text
                    recognitionSeconds = Date().timeIntervalSince(start)
                    warning = recognized.lowConfidence ? "部分识字不清晰，请核对原文。" : nil
                }
                clean = try TextPreparation.validated(clean)
                try Task.checkCancellation()
                guard id == jobID else { return }
                text = clean; phase = .translating
                let identity = try TranslationCache.key(text: clean, settings: snapshot, apiKey: "",
                    readingBlocks: nil, fromImageText: false, engine: "AppleTranslation")
                if snapshot.cacheTranslations, let hit = await pipeline.cache.value(for: identity) {
                    try Task.checkCancellation()
                    guard id == jobID else { return }
                    finishSystem(id: id, text: clean, translated: hit.text, settings: snapshot,
                        warning: warning, recognitionSeconds: recognitionSeconds, usedCache: true)
                    return
                }
                // Apple rejects a language translated into itself. Respect an
                // explicitly selected identical pair without calling any service.
                if snapshot.source.targetLanguage == snapshot.target {
                    finishSystem(id: id, text: clean, translated: clean, settings: snapshot,
                                 warning: warning, recognitionSeconds: recognitionSeconds)
                } else {
                    systemRequest = .init(id: id, text: clean, settings: snapshot, started: startedAt,
                                          warning: warning, recognitionSeconds: recognitionSeconds)
                }
            } catch is CancellationError {} catch {
                if id == jobID { self.error = error.localizedDescription; phase = .idle }
            }
        }
        #endif
    }

    func completeSystem(_ id: UUID, outcome: Result<String, Error>) {
        guard let request = systemRequest, id == jobID, id == request.id else { return }
        switch outcome {
        case .success(let translated):
            finishSystem(id: id, text: request.text, translated: translated, settings: request.settings,
                         warning: request.warning, recognitionSeconds: request.recognitionSeconds)
        case .failure(let failure):
            systemRequest = nil; phase = .idle
            error = failure is CancellationError ? "系统翻译已取消，可以重试。"
                : "系统翻译未完成：\(failure.localizedDescription)。请重试或切换 AI 翻译。"
        }
    }

    private func finishSystem(id: UUID, text: String, translated: String, settings: AppSettings,
                              warning: String?, recognitionSeconds: TimeInterval?, usedCache: Bool = false) {
        guard id == jobID else { return }
        var value = TranslationResult(original: text, translated: TranslationFormatting.normalized(translated),
            sourceLanguages: settings.source == .automatic ? LanguageDetector.describe(text) : settings.source.title,
            target: settings.target.title, engine: "系统翻译", elapsed: Date().timeIntervalSince(startedAt), warning: warning)
        guard !value.translated.isEmpty else {
            systemRequest = nil; phase = .idle; error = TranslationError.emptyResponse.localizedDescription; return
        }
        value.mode = .quick; value.recognitionSeconds = recognitionSeconds
        value.usedCache = usedCache
        if settings.cacheTranslations, !usedCache,
           let identity = try? TranslationCache.key(text: text, settings: settings, apiKey: "",
                readingBlocks: nil, fromImageText: false, engine: "AppleTranslation") {
            let output = TranslationOutput(text: value.translated, warning: nil)
            Task { await pipeline.cache.insert(output, for: identity) }
        }
        do { try store.record(value) } catch { value.warning = "译文已生成，但翻译记录保存失败。" }
        result = value; systemRequest = nil; phase = .idle
    }

    func clear() {
        cancel()
        text = ""; imageData = nil; preview = nil; result = nil; error = nil; ocrWarning = nil
    }

    func invalidateTranslation() {
        cancel()
        result = nil; error = nil
    }

    func modeChanged() {
        let shouldRecognizeAgain = imageData != nil && textCameFromOCR
        invalidateTranslation()
        if shouldRecognizeAgain { text = "" }
    }

    private func begin(_ stage: Phase) {
        cancel()
        error = nil
        result = nil
        startedAt = Date()
        phase = stage
    }
}
