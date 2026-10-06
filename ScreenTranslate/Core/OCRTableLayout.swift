import Foundation

/// A table requires a recognisable header and repeated, aligned rows. A row
/// of station names or independent form labels is not sufficient evidence.
enum OCRTableLayout {
    private static let headerWords: Set<String> = ["item", "qty", "quantity", "amount", "price", "departure", "platform", "destination",
        "商品", "項目", "数量", "金額", "価格", "発車", "ホーム", "行先", "品目", "时间", "站台", "目的地", "金额"]

    static func group(_ input: [[RecognizedLine]]) -> [[RecognizedLine]] {
        let rows = input.map { $0.sorted { $0.x < $1.x } }
        var output: [[RecognizedLine]] = [], index = 0
        while index < rows.count {
            let header = rows[index]
            guard (3...4).contains(header.count), header.allSatisfy({ $0.readingKind == nil }),
                  header.filter({ headerWords.contains($0.text.lowercased().trimmingCharacters(in: .whitespaces)) }).count >= 2 else {
                output.append(header); index += 1; continue
            }
            var matched = [header], cursor = index + 1
            while cursor < rows.count, aligned(rows[cursor], with: header),
                  gap(from: matched.last!, to: rows[cursor]) < 0.10 {
                matched.append(rows[cursor]); cursor += 1
            }
            // At least two data rows avoid turning an isolated toolbar into a table.
            let dataRows = matched.dropFirst().filter { $0.contains { $0.text.rangeOfCharacter(from: .decimalDigits) != nil } }
            guard dataRows.count >= 2 else { output.append(header); index += 1; continue }
            // Bilingual header lines are one header: each column keeps both
            // source labels, allowing the translator to express the label once.
            var displayRows: [[RecognizedLine]] = []
            for cells in matched {
                let headerRow = cells.filter { headerWords.contains($0.text.lowercased().trimmingCharacters(in: .whitespaces)) }.count >= 2
                if headerRow, let previous = displayRows.last,
                   previous.filter({ headerWords.contains($0.text.lowercased().components(separatedBy: " / ").first ?? "") }).count >= 2 {
                    displayRows[displayRows.count - 1] = zip(previous, cells).map { first, second in
                        var cell = first; cell.text += " / " + second.text
                        let top = max(first.y + first.height, second.y + second.height)
                        cell.y = min(first.y, second.y); cell.height = top - cell.y
                        return cell
                    }
                } else { displayRows.append(cells) }
            }
            for cells in displayRows {
                let isHeader = cells.filter { headerWords.contains($0.text.lowercased().components(separatedBy: " / ").first ?? "") }.count >= 2
                var line = cells[0]
                line.text = cells.map(\.text).joined(separator: "\t")
                let bottom = cells.map(\.y).min()!, top = cells.map { $0.y + $0.height }.max()!
                line.y = bottom; line.height = top - bottom
                line.width = cells.map { $0.x + $0.width }.max()! - line.x
                line.confidence = cells.map(\.confidence).min()!
                line.readingKind = isHeader ? .tableHeader : .tableRow
                output.append([line])
            }
            index = cursor
        }
        return output
    }

    private static func aligned(_ row: [RecognizedLine], with header: [RecognizedLine]) -> Bool {
        guard row.count == header.count, row.allSatisfy({ $0.readingKind == nil }) else { return false }
        return zip(row, header).allSatisfy { value, label in
            abs((value.x + value.width / 2) - (label.x + label.width / 2)) < 0.13
        }
    }

    private static func gap(from first: [RecognizedLine], to second: [RecognizedLine]) -> Double {
        first.map(\.y).min()! - second.map { $0.y + $0.height }.max()!
    }
}
