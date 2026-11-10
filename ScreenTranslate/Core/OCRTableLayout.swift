import Foundation

/// A table requires a recognisable header and repeated, aligned rows. A row
/// of station names or independent form labels is not sufficient evidence.
enum OCRTableLayout {
    private static let headerWords: Set<String> = ["item", "qty", "quantity", "amount", "price", "departure", "platform", "destination",
        "商品", "項目", "数量", "金額", "価格", "発車", "ホーム", "行先", "品目", "时间", "站台", "目的地", "金额", "単価", "小計", "税率", "税額", "合計", "備考", "在庫", "unit price", "tax", "subtotal", "total", "stock", "note", "单价", "小计", "税率", "备注"]

    static func group(_ input: [[RecognizedLine]]) -> [[RecognizedLine]] {
        let rows = input.map { $0.sorted { $0.x < $1.x } }
        var output: [[RecognizedLine]] = [], index = 0
        while index < rows.count {
            let header = rows[index]
            guard (3...8).contains(header.count), header.allSatisfy({ $0.readingKind == nil }),
                  header.filter({ headerWords.contains($0.text.lowercased().trimmingCharacters(in: .whitespaces)) }).count >= 2 else {
                output.append(header); index += 1; continue
            }
            var matched = [header], cursor = index + 1
            while cursor < rows.count, gap(from: matched.last!, to: rows[cursor]) < 0.10 {
                if let aligned = aligned(rows[cursor], with: header) {
                    matched.append(aligned); cursor += 1
                } else if matched.count > 1, rows[cursor].count == 1,
                          let wrapped = rows[cursor].first,
                          wrapped.text.rangeOfCharacter(from: .decimalDigits) == nil,
                          gap(from: matched.last!, to: rows[cursor]) < wrapped.height * 1.2,
                          let column = header.indices.first(where: { abs(header[$0].x - wrapped.x) < 0.035 }),
                          !matched[matched.count - 1][column].text.isEmpty {
                    matched[matched.count - 1][column].text += " " + wrapped.text
                    matched[matched.count - 1][column].confidence = min(matched[matched.count - 1][column].confidence, wrapped.confidence)
                    let cell = matched[matched.count - 1][column]
                    let bounds = OCRTextBox(x: cell.x, y: cell.y, width: cell.width, height: cell.height)
                        .union(.init(x: wrapped.x, y: wrapped.y, width: wrapped.width, height: wrapped.height))
                    matched[matched.count - 1][column].x = bounds.x
                    matched[matched.count - 1][column].y = bounds.y
                    matched[matched.count - 1][column].width = bounds.width
                    matched[matched.count - 1][column].height = bounds.height
                    cursor += 1
                } else { break }
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
                        let bounds = OCRTextBox(x: first.x, y: first.y, width: first.width, height: first.height)
                            .union(.init(x: second.x, y: second.y, width: second.width, height: second.height))
                        cell.x = bounds.x; cell.y = bounds.y; cell.width = bounds.width; cell.height = bounds.height
                        return cell
                    }
                } else { displayRows.append(cells) }
            }
            for cells in displayRows {
                let isHeader = cells.filter { headerWords.contains($0.text.lowercased().components(separatedBy: " / ").first ?? "") }.count >= 2
                var line = cells[0]
                line.text = cells.map(\.text).joined(separator: "\t")
                line.cellBoxes = cells.map { .init(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
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

    private static func aligned(_ row: [RecognizedLine], with header: [RecognizedLine]) -> [RecognizedLine]? {
        guard (2...header.count).contains(row.count), row.allSatisfy({ $0.readingKind == nil }) else { return nil }
        let boundaries = zip(header, header.dropFirst()).map { ($0.x + $0.width + $1.x) / 2 }
        var cells: [Int: RecognizedLine] = [:]
        for value in row {
            let center = value.x + value.width / 2
            let column = boundaries.firstIndex(where: { center < $0 }) ?? header.count - 1
            guard cells[column] == nil else { return nil }
            let label = header[column]
            // Accept left-, centre- and right-aligned data, but never a box
            // spanning multiple columns or a value in an ambiguous gutter.
            let alignedEdge = min(abs(value.x - label.x), abs(center - label.x - label.width / 2),
                                  abs(value.x + value.width - label.x - label.width))
            guard alignedEdge < 0.10,
                  column == 0 || value.x >= boundaries[column - 1] - 0.025,
                  column == header.count - 1 || value.x + value.width <= boundaries[column] + 0.025 else { return nil }
            cells[column] = value
        }
        return header.indices.map { index in
            if let value = cells[index] { return value }
            var blank = header[index]
            blank.text = ""; blank.y = row[0].y; blank.height = row[0].height; blank.confidence = 1
            return blank
        }
    }

    private static func gap(from first: [RecognizedLine], to second: [RecognizedLine]) -> Double {
        first.map(\.y).min()! - second.map { $0.y + $0.height }.max()!
    }
}
