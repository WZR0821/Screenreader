import Foundation

/// Geometry is supplied exclusively by local OCR, never by translated/model text.
enum ImageTranslationLayout {
    struct Item: Equatable, Identifiable, Sendable {
        var blockID: Int
        var cell: Int
        var text: String
        var original: String
        var box: OCRTextBox
        var vertical: Bool
        var heading: Bool
        var id: String { "\(blockID)-\(cell)" }
    }

    static func clipped(_ box: OCRTextBox) -> OCRTextBox? {
        guard box.isValid else { return nil }
        if box.x >= 0, box.y >= 0, box.x + box.width <= 1, box.y + box.height <= 1 { return box }
        let left = max(0, box.x), right = min(1, box.x + box.width)
        let bottom = max(0, box.y), top = min(1, box.y + box.height)
        guard right > left, top > bottom else { return nil }
        return .init(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    static func items(in result: TranslationResult) -> [Item] {
        guard result.mode != .visual, result.imageMode != .visual,
              let blocks = result.blocks, Set(blocks.map(\.id)).count == blocks.count else { return [] }
        let english = ["英语", "English"].contains(result.target)
        return blocks.flatMap { block -> [Item] in
            guard let original = block.original, !original.isEmpty, !block.text.isEmpty,
                  let source = block.sourceBox, let box = clipped(source) else { return [] }
            if block.kind == .field, let boxes = block.sourceCellBoxes, boxes.count == 2,
               let sourceParts = ReadingBlock(id: block.id, text: original, kind: .field).fieldParts,
               let translated = block.fieldParts,
               let labelBox = clipped(boxes[0]), let valueBox = clipped(boxes[1]) {
                return [Item(blockID: block.id, cell: 0, text: translated.label, original: sourceParts.label,
                             box: labelBox, vertical: false, heading: false),
                        Item(blockID: block.id, cell: 1, text: translated.value, original: sourceParts.value,
                             box: valueBox, vertical: false, heading: false)]
            }
            if let cells = block.tableCells, let boxes = block.sourceCellBoxes,
               cells.count == boxes.count, original.components(separatedBy: "\t").count == cells.count {
                let originals = original.components(separatedBy: "\t")
                return cells.indices.compactMap { index in
                    guard !cells[index].isEmpty, let cellBox = clipped(boxes[index]) else { return nil }
                    return Item(blockID: block.id, cell: index, text: cells[index], original: originals[index],
                                box: cellBox, vertical: false, heading: block.kind == .tableHeader)
                }
            }
            return [Item(blockID: block.id, cell: 0, text: block.text.replacingOccurrences(of: "\t", with: "  "),
                         original: original, box: box, vertical: block.sourceVertical == true && !english,
                         heading: block.kind == .heading)]
        }
    }
}
