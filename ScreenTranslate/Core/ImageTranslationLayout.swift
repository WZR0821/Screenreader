import Foundation
import CoreGraphics

/// Geometry is supplied exclusively by local OCR, never by translated/model text.
enum ImageTranslationLayout {
    /// How a single source line sat on the screen, so a shorter translation
    /// stays under a centred title or against a right-hand value column.
    enum Alignment: Equatable, Sendable { case leading, center, trailing }

    struct Item: Equatable, Identifiable, Sendable {
        var blockID: Int
        var cell: Int
        var text: String
        var original: String
        var box: OCRTextBox
        var vertical: Bool
        var heading: Bool
        /// One source line across the reading direction, normalised like
        /// `box`; nil for results saved before 1.3.3.
        var lineHeight: Double? = nil
        /// Source lines inside `box`.
        var rows: Int = 1
        var alignment: Alignment = .leading
        var id: String { "\(blockID)-\(cell)" }
    }

    /// An item on a canvas of a given size, in points with a top-left origin.
    struct Placement: Equatable, Sendable {
        /// The opaque label: the source text plus a margin that covers
        /// antialiased edges and Vision's slightly tight boxes.
        var tile: CGRect
        /// The source text itself.
        var text: CGRect
        /// One source line across the reading direction.
        var line: CGFloat
        /// Distance between consecutive source lines when the box holds
        /// several evenly spaced lines.
        var pitch: CGFloat?
        var rows: Int
        /// The box holds exactly one source line.
        var single: Bool
        var alignment: Alignment
        /// How far `tile` extends beyond `text` (less at the canvas edge).
        var padding: CGFloat

        /// The same placement measured from the tile's own corner.
        var local: Placement {
            var value = self
            value.text = text.offsetBy(dx: -tile.minX, dy: -tile.minY)
            value.tile = CGRect(origin: .zero, size: tile.size)
            return value
        }
    }

    static func placement(of item: Item, in size: CGSize) -> Placement {
        let box = item.box
        let text = CGRect(x: box.x * size.width, y: (1 - box.y - box.height) * size.height,
                          width: box.width * size.width, height: box.height * size.height)
        let extent = item.vertical ? text.width : text.height
        let measured = item.lineHeight.map { CGFloat($0) * (item.vertical ? size.width : size.height) }
        // Older results only know the whole box: never let a tall paragraph
        // box choose a heading-sized font.
        let line = min(extent, measured.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 32)
        var rows = max(1, item.rows), pitch: CGFloat?
        if rows > 1 {
            let spacing = (extent - line) / CGFloat(rows - 1)
            if spacing >= line * 0.9, spacing <= line * 3 { pitch = spacing } else { rows = 1 }
        }
        let single = rows == 1 && extent <= line * 1.6
        let padding = min(5, max(1.5, line * 0.12))
        let tile = text.insetBy(dx: -padding, dy: -padding).intersection(CGRect(origin: .zero, size: size))
        return .init(tile: tile, text: text, line: line, pitch: pitch, rows: rows, single: single,
                     alignment: single && !item.vertical ? item.alignment : .leading, padding: padding)
    }

    /// Only clear cases: a short line centred on the screen, or a value that
    /// ends at the right margin. Everything else keeps its left edge.
    static func alignment(of box: OCRTextBox) -> Alignment {
        if box.x > 0.08, box.width < 0.7, abs(box.x + box.width / 2 - 0.5) <= 0.02 { return .center }
        if box.x > 0.5, box.x + box.width >= 0.9 { return .trailing }
        return .leading
    }

    /// Cells have no line count of their own; estimate it from the block's line.
    static func rows(in extent: Double, line: Double?) -> Int {
        guard let line, line > 0, extent > line * 1.6 else { return 1 }
        return max(1, Int(((extent - line) / (line * 1.3)).rounded()) + 1)
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
            // A vertical column's line is its width; it means nothing once the
            // translation is set horizontally.
            let line = block.sourceVertical == true ? nil : block.sourceLineHeight
            func cell(_ index: Int, text: String, original: String, box: OCRTextBox, heading: Bool) -> Item {
                Item(blockID: block.id, cell: index, text: text, original: original, box: box, vertical: false,
                     heading: heading, lineHeight: line, rows: rows(in: box.height, line: line), alignment: alignment(of: box))
            }
            if block.kind == .field, let boxes = block.sourceCellBoxes, boxes.count == 2,
               let sourceParts = ReadingBlock(id: block.id, text: original, kind: .field).fieldParts,
               let translated = block.fieldParts,
               let labelBox = clipped(boxes[0]), let valueBox = clipped(boxes[1]) {
                return [cell(0, text: translated.label, original: sourceParts.label, box: labelBox, heading: false),
                        cell(1, text: translated.value, original: sourceParts.value, box: valueBox, heading: false)]
            }
            if let cells = block.tableCells, let boxes = block.sourceCellBoxes,
               cells.count == boxes.count, original.components(separatedBy: "\t").count == cells.count {
                let originals = original.components(separatedBy: "\t")
                return cells.indices.compactMap { index in
                    guard !cells[index].isEmpty, let cellBox = clipped(boxes[index]) else { return nil }
                    return cell(index, text: cells[index], original: originals[index], box: cellBox,
                                heading: block.kind == .tableHeader)
                }
            }
            let vertical = block.sourceVertical == true && !english
            return [Item(blockID: block.id, cell: 0, text: block.text.replacingOccurrences(of: "\t", with: "  "),
                         original: original, box: box, vertical: vertical, heading: block.kind == .heading,
                         lineHeight: vertical ? block.sourceLineHeight : line,
                         rows: vertical || line != nil ? block.sourceLineCount ?? 1 : 1,
                         alignment: vertical ? .leading : alignment(of: box))]
        }
    }
}
