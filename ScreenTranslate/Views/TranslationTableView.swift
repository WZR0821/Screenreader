import SwiftUI

struct TranslationTableView: View {
    let blocks: [ReadingBlock]
    let firstIndex: Int
    let reader: ReaderPreferences
    let textScale: Double
    var target: String = ""
    var onReviewBlock: ((Int) -> Void)? = nil
    var isWorking = false
    var reviewableIDs = Set<Int>()
    private var columns: Int { blocks.map { $0.tableCells?.count ?? 0 }.max() ?? 0 }
    private var points: Double { reader.fontSize * textScale }
    private var cellWidth: Double { max(columns > 3 ? 112 : 88, points * 4.5) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if columns > 3 { Text("左右滑动查看全部 \(columns) 列").font(.caption).foregroundStyle(.secondary) }
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { offset, block in
                        HStack(alignment: .center, spacing: 4) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(Array((block.tableCells ?? []).enumerated()), id: \.offset) { column, value in
                                JapaneseTranslationText(text: value.isEmpty ? "—" : value, target: target,
                                    reader: reader, textScale: textScale, semibold: block.kind == .tableHeader)
                                    .frame(width: cellWidth, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.vertical, 9)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel((block.tableCells ?? []).map { $0.isEmpty ? "空白" : $0 }.joined(separator: "，"))
                            .accessibilityIdentifier(firstIndex + offset == 0 ? "translationResult" : "translationParagraph-\(firstIndex + offset)")
                            .contentShape(Rectangle())
                        if let onReviewBlock, reviewableIDs.contains(block.id) {
                            TranslationReviewButton(block: block) { onReviewBlock(block.id) }
                                .disabled(isWorking)
                        }
                        }
                        if offset < blocks.count - 1 { Divider() }
                    }
                }.textSelection(.enabled).padding(.bottom, 4)
            }.accessibilityIdentifier("translationTable")
        }
    }
}
