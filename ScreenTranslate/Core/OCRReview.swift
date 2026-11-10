import Foundation

enum OCRTextDirection: String, CaseIterable, Identifiable {
    case automatic, horizontal, vertical
    var id: String { rawValue }
    var title: String {
        switch self { case .automatic: return "自动"; case .horizontal: return "横排"; case .vertical: return "竖排日语" }
    }
}

struct OCRReviewItem: Identifiable, Equatable {
    var id: Int
    var text: String
    var box: OCRTextBox
    var reasons: [String]
    var alternatives: [String]
}

enum OCRReview {
    static func items(_ lines: [RecognizedLine], imageWidth: Int, imageHeight: Int, japanese: Bool) -> [OCRReviewItem] {
        lines.enumerated().compactMap { index, line in
            var reasons: [String] = []
            if line.confidence < 0.7 { reasons.append("识字置信度较低") }
            let glyphSize = line.vertical ? line.width * Double(imageWidth) : line.height * Double(imageHeight)
            if glyphSize < 18 { reasons.append("文字较小") }
            if line.vertical { reasons.append("竖排阅读顺序与标点") }
            if OCRDateReview.range(in: line.text) != nil { reasons.append("日期需要核对") }
            if OCRCurrencyReview.needsReview(line, in: lines) { reasons.append("金额或货币符号") }
            if japanese && OCRScriptReview.needsReview(line.text) { reasons.append("日语字形可能混淆") }
            guard !reasons.isEmpty else { return nil }
            return .init(id: index, text: line.text, box: .init(x: line.x, y: line.y, width: line.width, height: line.height),
                         reasons: reasons, alternatives: line.alternatives.filter { $0 != line.text })
        }
    }
}
