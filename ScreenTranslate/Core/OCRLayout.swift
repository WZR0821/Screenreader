import Foundation

struct OCRTextBox: Equatable {
    var x: Double; var y: Double; var width: Double; var height: Double
}

struct RecognizedLine: Equatable {
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var confidence: Float
    var dateBox: OCRTextBox? = nil
    var currencyBox: OCRTextBox? = nil
    var glyphEm: Double? = nil
    var readingKind: ReadingBlock.Kind? = nil
}

enum OCRLayout {
    static func readableLines(_ lines: [RecognizedLine], aspectRatio: Double) -> [RecognizedLine] {
        let phoneShape = (1.7...2.5).contains(aspectRatio)
        let clock = lines.first { line in
            line.x < 0.4 && line.y > 0.93 && line.text.range(
                of: #"^\s*[0-2]?[0-9][:：][0-5][0-9](?:\s*[1IlAa！!])?\s*$"#,
                options: .regularExpression) != nil
        }
        let hasStatusBar = phoneShape && ((clock != nil && lines.contains {
            $0.x > 0.65 && $0.y > 0.93
        }))
        let navigation: Set<String> = ["帖子", "返回", "关注", "推荐", "首页", "搜索", "通知", "消息", "Post", "Posts", "Home", "Back"]
        let symbols: Set<String> = ["←", "→", "‹", "›", "×", "⌄", "⌃", "⋯"]
        return lines.compactMap { original in
            var line = original
            line.text = original.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.text.isEmpty else { return nil }
            // Only a clock plus right-side status evidence establishes screenshot chrome.
            if hasStatusBar, line.y > 0.94 { return nil }
            if hasStatusBar, let clock, abs(line.y - clock.y) < max(clock.height, line.height) * 1.6 { return nil }
            if hasStatusBar, (line.y > 0.87 || line.y < 0.07), navigation.contains(line.text) { return nil }
            // A sender avatar is presentation chrome, not an isolated digit.
            // Require both email header labels beside the same small initial.
            if line.text.count == 1, line.text.first?.isLetter == true,
               line.x < 0.16, line.width < 0.08, line.height < 0.05 {
                let nearby = lines.filter { $0.x > line.x + line.width && abs($0.y - line.y) < 0.075 }
                if nearby.contains(where: { $0.text.lowercased().hasPrefix("from:") }),
                   nearby.contains(where: { $0.text.lowercased().hasPrefix("to:") }),
                   nearby.contains(where: { $0.text.contains("@") }) { return nil }
            }
            // A long, thin separator between text regions is decoration. Stars,
            // emoji, mathematical operators and standalone numbers are not.
            if line.width > 0.3, line.height < 0.018,
               line.text.range(of: #"^[─━—_－]{3,}$"#, options: .regularExpression) != nil,
               lines.contains(where: { $0.y > line.y + line.height && $0.text.rangeOfCharacter(from: .alphanumerics) != nil }),
               lines.contains(where: { $0.y + $0.height < line.y && $0.text.rangeOfCharacter(from: .alphanumerics) != nil }) { return nil }
            let hasTextOnRight = lines.contains { other in
                other.x >= line.x + line.width && other.x - line.x - line.width < 0.10
                    && abs(other.y + other.height / 2 - line.y - line.height / 2) < max(other.height, line.height) * 0.6
                    && other.text.rangeOfCharacter(from: .alphanumerics) != nil
            }
            let hasTextOnLeft = lines.contains { other in
                line.x >= other.x + other.width && line.x - other.x - other.width < 0.04
                    && abs(other.y + other.height / 2 - line.y - line.height / 2) < max(other.height, line.height) * 0.6
                    && other.text.rangeOfCharacter(from: .alphanumerics) != nil
            }
            let sameRow: (RecognizedLine) -> Bool = { other in
                abs((other.y + other.height / 2) - (line.y + line.height / 2)) < max(other.height, line.height) * 0.9
            }
            let inlineRelation = ["×", "←", "→", "‹", "›", "<", ">", "=", "＝"].contains(line.text)
                && lines.contains(where: { $0.x + $0.width <= line.x && sameRow($0)
                    && $0.text.rangeOfCharacter(from: .alphanumerics) != nil })
                && lines.contains(where: { $0.x >= line.x + line.width && sameRow($0)
                    && $0.text.rangeOfCharacter(from: .alphanumerics) != nil })
            if symbols.contains(line.text) && !inlineRelation { return nil }
            if hasStatusBar, !inlineRelation, line.y > 0.84 && line.y < 0.945, line.x > 0.82, line.width < 0.09,
               ["=", "＝", "≡", "Q!", "Q！"].contains(line.text),
               lines.contains(where: { $0.x < 0.6 && sameRow($0) && $0.text.count >= 3
                   && $0.text.rangeOfCharacter(from: .letters) != nil
                   && $0.text.rangeOfCharacter(from: .decimalDigits) == nil }) { return nil }
            // An increment/decrement control is identified by its quantity
            // label and number on the same row. '+' elsewhere may be content.
            let quantityControl = lines.contains { other in
                sameRow(other) && other.text.range(of: #"^(?:数量|quantity)\s*[：:]?\s*\d*\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
            }
            if (["+", "＋", "−", "-"].contains(line.text) || (line.text == "十" && line.confidence < 0.7)), line.width < 0.08,
               quantityControl,
               lines.contains(where: { $0.text.range(of: #"^\d+$"#, options: .regularExpression) != nil && sameRow($0) }),
               !lines.contains(where: { ["=", "×", "÷"].contains($0.text) && sameRow($0) }) { return nil }
            if hasStatusBar, !inlineRelation, [">", "<"].contains(line.text), line.width < 0.06,
               (line.y < 0.10 || line.y > 0.87), (line.x < 0.1 || line.x > 0.7),
               lines.contains(where: { $0 != original && sameRow($0) && $0.text.count > 4 }) { return nil }
            if line.text.range(of: #"^[!！:：.;；,，。・·•…|丨\s]+$"#, options: .regularExpression) != nil,
               !(hasTextOnRight && ["・", "•", "·", "●", ":", "："].contains(line.text)),
               !(hasTextOnLeft && line.text.count <= 3) { return nil }
            if hasStatusBar, line.width < 0.06, line.confidence < 0.55,
               ["く", "へ", "v", "V", "✓", "√", "+", "−", "-", "○", "◯"].contains(line.text),
               lines.contains(where: { ($0.x > line.x + line.width || $0.x + $0.width < line.x)
                   && abs($0.y - line.y) < max($0.height, line.height) }) { return nil }
            // Position/size/confidence alone cannot distinguish a count from a
            // UI badge. Keep standalone digits outside a confirmed status bar.
            // This is an exact standalone UI label, never a substring replacement.
            if hasStatusBar, ["显示翻译", "查看翻译", "Translate post", "Show translation"].contains(line.text) { return nil }
            // Some screenshot icons are returned in the same observation as a
            // bottom action. Restrict cleanup to known actions, never sentences.
            if hasStatusBar, line.y < 0.15, line.text.range(of: #"^[!！]\s*(?:カートに追加する|購入手続きへ|Checkout|View tickets)(?:\s|/|／|$)"#, options: [.regularExpression, .caseInsensitive]) != nil {
                line.text = String(line.text.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            return line
        }
    }

    static func assemble(_ lines: [RecognizedLine]) -> String {
        let ordered = orderedLines(lines)
        guard !ordered.isEmpty else { return "" }
        let heights = ordered.map(\.height).sorted()
        let typicalHeight = heights[heights.count / 2]
        var result = ""
        var previous: RecognizedLine?
        for line in ordered {
            if let last = previous {
                if startsParagraph(after: last, line: line, typicalHeight: typicalHeight) { result += "\n\n" }
                else if isAmount(last.text) || isAmount(line.text) || ReadingBlock.isListRow(line.text) { result += "\n" }
                else { result += needsSpace(between: last.text, and: line.text) ? " " : "" }
            }
            result += line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            previous = line
        }
        return result
    }

    static func readingBlocks(_ lines: [RecognizedLine]) -> [ReadingBlock] {
        let ordered = orderedLines(lines)
        guard !ordered.isEmpty else { return [] }
        let heights = ordered.map(\.height).sorted()
        let typical = heights[heights.count / 2]
        let candidates = ordered.filter { !$0.text.contains("\n") && !$0.text.contains("：") }
        let bodyEms = candidates.filter { endsSentence($0.text) && $0.text.count >= 10 }.map(estimatedEm).sorted()
        let ems = bodyEms.count >= 2 ? bodyEms : candidates.map(estimatedEm).sorted()
        let typicalEm = ems.isEmpty ? 0 : ems[ems.count / 2]
        var blocks: [ReadingBlock] = []
        var previous: RecognizedLine?
        for (index, line) in ordered.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let field = text.range(of: #"(?:価格|价格|数量|合計|总计|Quantity|Price|Total)[：:]|[¥￥$€£]\s*\d|\d[\d,.，．]*\s*(?:円|元|日元|yen|USD|JPY)"#,
                options: [.regularExpression, .caseInsensitive]) != nil && text.count < 160
            let dateOrTime = text.range(of: #"^(?:\d{4}[/.-]\d{1,2}[/.-]\d{1,2}|(?:(?:OPEN|START|開場|開演)\s*[|｜:：]?\s*)?\d{1,2}[:：]\d{2}(?:\s*[~〜～–-]\s*\d{1,2}[:：]\d{2})?)$"#,
                options: [.regularExpression, .caseInsensitive]) != nil
            let prose = text.count >= 18 && (endsSentence(text) || text.contains("。") || endsInLatinConnector(text))
            let choiceHeading = text.count < 90 && ["必須選択", "必选", "Required", "Optional"].contains(where: text.contains)
            let heading = text.rangeOfCharacter(from: .alphanumerics) != nil && !isMetadata(text) && !field && !dateOrTime && !prose && !isAmount(text) && !ReadingBlock.isListRow(text) && !text.contains("\n") && text.count <= 180
                && (choiceHeading || (line.height > typical * 1.2 && estimatedEm(line) > typicalEm * 1.08) || estimatedEm(line) > typicalEm * 1.22)
            let next = index + 1 < ordered.count ? ordered[index + 1] : nil
            let listLike: (RecognizedLine?) -> Bool = { other in
                guard let other else { return false }
                let gap = abs(line.y - other.y)
                return text.count <= 90 && other.text.count <= 90
                    && !endsSentence(text) && !endsSentence(other.text)
                    && !isMetadata(text) && !isMetadata(other.text)
                    && !isAmount(text) && !isAmount(other.text)
                    && abs(line.x - other.x) < 0.05
                    && max(line.height, other.height) / max(0.0001, min(line.height, other.height)) < 1.3
                    && gap > max(line.height, other.height) * 1.6 && gap < max(line.height, other.height) * 8
            }
            let list = ReadingBlock.isListRow(text) || (!heading && !field && !dateOrTime && (listLike(previous) || listLike(next)))
            let kind: ReadingBlock.Kind = line.readingKind ?? (field || dateOrTime ? .field : (heading ? .heading : (list ? .listItem : .paragraph)))
            if let last = previous, let block = blocks.last {
                let near = !startsParagraph(after: last, line: line, typicalHeight: typical)
                // Wrapped headings remain one heading; list options stay separate.
                let continuation = block.kind == kind && (kind == .paragraph || kind == .heading) && near
                let wrappedList = block.kind == .listItem && ReadingBlock.isListRow(block.text)
                    && !ReadingBlock.isListRow(text) && kind == .paragraph && near
                    && !endsSentence(last.text) && line.x >= last.x - 0.015
                let captionGap = last.y - (line.y + line.height)
                let nearCaption = captionGap >= -max(last.height, line.height) * 0.4
                    && captionGap < max(last.height, line.height) * 1.2
                let itemLabel = block.text.components(separatedBy: "：").first ?? block.text
                let bilingualItem = block.kind == .field && nearCaption
                    && (itemLabel.contains("/") || itemLabel.contains("／") || JapaneseText.kanaCount(itemLabel) >= 2)
                    && block.text.unicodeScalars.contains(where: { $0.value >= 0x3040 })
                    && !text.unicodeScalars.contains(where: { $0.value >= 0x3040 })
                    && text.rangeOfCharacter(from: .decimalDigits) == nil && !endsSentence(text)
                    && text.count < 50 && abs(line.x - last.x) < 0.1
                let bilingualHeading = block.kind == .heading && nearCaption && !endsSentence(block.text)
                    && JapaneseText.kanaCount(block.text) >= 2 && text.count < 50
                    && text.range(of: #"^[A-Za-z][A-Za-z'’ &/-]+$"#, options: .regularExpression) != nil
                    && abs(line.x - last.x) < 0.1
                let trailingPrice = isAmount(text) && text.contains(where: { !$0.isNumber && !$0.isWhitespace })
                    && near && !isAmount(last.text) && (block.kind == .paragraph || block.kind == .listItem)
                if continuation || wrappedList || bilingualItem || bilingualHeading || trailingPrice {
                    if bilingualItem, let separator = block.text.firstIndex(of: "：") {
                        // The English caption belongs to the item label. Putting
                        // it after the amount breaks the label/value relationship.
                        let label = String(block.text[..<separator]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "/／")))
                        let amount = String(block.text[block.text.index(after: separator)...])
                        blocks[blocks.count - 1].text = label + " / " + text + "：" + amount
                    } else if bilingualHeading {
                        blocks[blocks.count - 1].text += " / " + text
                    } else {
                        blocks[blocks.count - 1].text += trailingPrice ? "\n" + text : (needsSpace(between: block.text, and: text) ? " " : "") + text
                    }
                    if trailingPrice { blocks[blocks.count - 1].kind = .field }
                    previous = line; continue
                }
            }
            blocks.append(.init(id: blocks.count + 1, text: text, kind: kind))
            previous = line
        }
        return blocks
    }

    private static func orderedLines(_ input: [RecognizedLine]) -> [RecognizedLine] {
        let measured = input.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { line in
            var line = line; line.glyphEm = estimatedEm(line); return line
        }
        let lines = groupStackedPrices(groupAdjacentPrices(groupFormValues(measured)))
        // Group rows using geometry rather than a non-transitive fuzzy sort comparator.
        let topDown = lines.sorted { ($0.y + $0.height) > ($1.y + $1.height) }
        var rows: [[RecognizedLine]] = []
        for line in topDown {
            if let last = rows.last, let anchor = last.first,
               abs((line.y + line.height / 2) - (anchor.y + anchor.height / 2))
                < min(line.height, anchor.height) * 0.45 {
                rows[rows.count - 1].append(line)
            } else { rows.append([line]) }
        }
        let structured = OCRTableLayout.group(rows)
        return structured.flatMap { row -> [RecognizedLine] in
            // Vision sometimes splits one visual line into adjacent text boxes.
            // Join those boxes before paragraph decisions; retain separate columns.
            var joined: [RecognizedLine] = []
            for line in row.sorted(by: { $0.x < $1.x }) {
                if var last = joined.last, last.readingKind == nil, line.readingKind == nil,
                   (line.x - (last.x + last.width) < max(0.025, min(line.height, last.height) * 0.7)
                    || ["必須選択", "必选", "Required", "Optional"].contains(line.text)
                    || (isAmount(line.text) && !isAmount(last.text))) {
                    let requiredLabel = ["必須選択", "必选", "Required", "Optional"].contains(line.text)
                    last.text += (requiredLabel ? "　" : (needsSpace(between: last.text, and: line.text) ? " " : "")) + line.text
                    last.width = max(last.x + last.width, line.x + line.width) - last.x
                    last.confidence = min(last.confidence, line.confidence)
                    joined[joined.count - 1] = last
                } else { joined.append(line) }
            }
            return joined
        }
    }

    private static func startsParagraph(after last: RecognizedLine, line: RecognizedLine, typicalHeight: Double) -> Bool {
                let gap = last.y - (line.y + line.height)
                let overlap = min(last.x + last.width, line.x + line.width) - max(last.x, line.x)
                let differentColumn = overlap < min(last.width, line.width) * 0.2
        let containsRows = last.text.contains("\n") || line.text.contains("\n")
        let structuredRow = last.readingKind != nil || line.readingKind != nil
                // A title and its description often have little whitespace but
                // visibly different type sizes. Do not glue them together.
        let latinWrap = endsInLatinConnector(last.text)
        let latinPair = [last.text, line.text].allSatisfy { $0.count >= 8 && !$0.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) }
        let emChange = max(estimatedEm(last), estimatedEm(line)) / max(0.0001, min(estimatedEm(last), estimatedEm(line)))
                let sizeChange = !latinWrap && (!latinPair || emChange > 1.16)
                    && max(last.height, line.height) / max(0.0001, min(last.height, line.height)) > 1.16
                    && gap > min(last.height, line.height) * 0.28
                let independentShortRow = last.text.count < 28 && line.text.count > 28
                    && !latinWrap
                    && gap > min(last.height, line.height) * 0.05
                    && !last.text.hasSuffix("/")
                    && !(last.height > typicalHeight * 1.15 && line.height > typicalHeight * 1.15)
        let bilingualLabel = last.text.count <= 90 && !endsSentence(last.text)
            && last.text.rangeOfCharacter(from: .decimalDigits) == nil
            && last.text.range(of: #"[\p{Han}\p{Hiragana}\p{Katakana}].*[／/]\s*[A-Za-z]"#, options: .regularExpression) != nil
            && endsSentence(line.text) && line.text.count >= 20
            && gap > min(last.height, line.height) * 0.28
        let noteBoundary = ["すべて税込", "税込", "税抜", "Tax included", "All prices include tax."].contains(last.text)
        let scriptTransition = endsSentence(last.text)
            && (JapaneseText.kanaCount(last.text) >= 2) != (JapaneseText.kanaCount(line.text) >= 2)
        return isMetadata(last.text) || isMetadata(line.text) || noteBoundary || scriptTransition || structuredRow || containsRows || gap > max(last.height, line.height) * 0.85 || differentColumn || sizeChange || independentShortRow || bilingualLabel
    }

    private static func isAmount(_ text: String) -> Bool {
        let normalized = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        return normalized.range(of: #"^\s*[¥￥$€£]?\s*[0-9][0-9\s,.]*(?:円|元|日元|ドル|yen|JPY|USD)?(?:起|から|〜|~)?\s*(?:[（(]\s*(?:税込|税抜|税別|含税|税前|tax included|incl\.? tax)\s*[）)])?\s*$"#,
            options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return "。！？.!?".contains(last)
    }

    private static func isMetadata(_ text: String) -> Bool {
        // Sender/recipient/URL rows are fields, not an implied bulleted list.
        text.range(of: #"^\S+@\S+$"#, options: .regularExpression) != nil || text.hasPrefix("https://") || text.hasPrefix("http://")
            || text.range(of: #"^(?:From|To|Cc|Bcc|Subject|送信者|宛先|件名|发件人|收件人)[：:]"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func endsInLatinConnector(_ text: String) -> Bool {
        !endsSentence(text) && text.range(of: #"\b(?:at|before|after|the|a|an|on|of|in|to|and|or|from|for|with|by|until|between|during|is|are|was|be|than)\s*$"#,
            options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func estimatedEm(_ line: RecognizedLine) -> Double {
        if let estimate = line.glyphEm { return estimate }
        // A lowercase heading may have the same bounding-box height as a body
        // line with descenders. Horizontal glyph size provides a second cue.
        let units = line.text.unicodeScalars.reduce(0.0) { total, scalar in
            if scalar.value >= 0x2E80 { return total + 1 }
            if CharacterSet.whitespaces.contains(scalar) { return total + 0.28 }
            if CharacterSet.uppercaseLetters.contains(scalar) { return total + 0.65 }
            if CharacterSet.alphanumerics.contains(scalar) { return total + 0.5 }
            return total + 0.3
        }
        return line.width / max(1, units)
    }

    private static func groupFormValues(_ input: [RecognizedLine]) -> [RecognizedLine] {
        let labels: Set<String> = ["数量", "価格", "税込価格", "税抜価格", "販売価格", "通常価格", "价格", "合計", "总计",
            "重量", "送料", "在庫", "人数", "日付", "入場時間", "予約番号", "金額", "最低文字数",
            "quantity", "price", "total", "total paid", "weight", "shipping", "stock", "guests", "date", "entry time", "reference", "minimum length"]
        func isLabel(_ line: RecognizedLine) -> Bool {
            labels.contains(line.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        func sameRow(_ lhs: RecognizedLine, _ rhs: RecognizedLine) -> Bool {
            abs((lhs.y + lhs.height / 2) - (rhs.y + rhs.height / 2)) < max(lhs.height, rhs.height) * 0.85
        }
        var consumed = Set<Int>()
        var grouped: [RecognizedLine] = []
        for (index, label) in input.enumerated() where isLabel(label) {
            if consumed.contains(index) { continue }
            let priceLabel = label.text.contains("価格") || ["price", "价格"].contains(label.text.lowercased())
            let values = input.enumerated().filter { i, value in
                i != index && !consumed.contains(i) && !isLabel(value)
                    && value.x > label.x + label.width + 0.015
                    && abs((value.y + value.height / 2) - (label.y + label.height / 2)) < max(label.height, value.height) * (priceLabel ? 2.0 : 0.85)
                    && value.text.rangeOfCharacter(from: .decimalDigits) != nil
                    && !input.contains(where: { other in
                        other != label && isLabel(other) && sameRow(label, other)
                            && other.x > label.x && other.x < value.x
                    })
                    && !input.contains(where: { other in
                        other != label && isLabel(other) && other.x < value.x
                            && abs(other.y - label.y) > max(other.height, label.height) * 0.4
                            && abs(other.y + other.height / 2 - value.y - value.height / 2)
                                <= abs(label.y + label.height / 2 - value.y - value.height / 2) + 0.0001
                    })
            }.sorted { $0.element.y > $1.element.y }
            guard !values.isEmpty else { continue }
            var block = label
            block.readingKind = .field
            if values.count == 1 { block.text += "：" + values[0].element.text }
            else { block.text += "\n" + values.map(\.element.text).joined(separator: "\n") }
            let bottom = min(label.y, values.map(\.element.y).min()!)
            let top = max(label.y + label.height, values.map { $0.element.y + $0.element.height }.max()!)
            block.y = bottom; block.height = top - bottom
            block.width = max(label.x + label.width, values.map { $0.element.x + $0.element.width }.max()!) - label.x
            grouped.append(block); consumed.insert(index)
            values.forEach { consumed.insert($0.offset) }
        }
        return input.enumerated().filter { !consumed.contains($0.offset) }.map(\.element) + grouped
    }

    private static func groupAdjacentPrices(_ input: [RecognizedLine]) -> [RecognizedLine] {
        func hasMenuCaption(_ label: RecognizedLine) -> Bool {
            guard label.text.count <= 24, JapaneseText.kanaCount(label.text) >= 2,
                  label.text.hasSuffix("!") || label.text.hasSuffix("！") else { return false }
            return input.contains { caption in
                let gap = label.y - (caption.y + caption.height)
                return caption.text.count < 50
                    && caption.text.range(of: #"^[A-Za-z][A-Za-z'’ &/-]+$"#, options: .regularExpression) != nil
                    && abs(caption.x - label.x) < 0.08
                    && gap >= -max(label.height, caption.height) * 0.5
                    && gap < max(label.height, caption.height) * 1.3
            }
        }
        var consumed = Set<Int>(), grouped: [RecognizedLine] = []
        for (index, amount) in input.enumerated() where amount.readingKind == nil && isAmount(amount.text)
            && amount.text.range(of: #"[¥￥$€£]|円|yen|JPY|USD"#, options: [.regularExpression, .caseInsensitive]) != nil {
            guard !consumed.contains(index) else { continue }
            let candidates = input.enumerated().filter { i, label in
                guard i != index, !consumed.contains(i), label.readingKind == nil,
                      label.text.count <= 45, (!endsSentence(label.text) || hasMenuCaption(label)), !ReadingBlock.isListRow(label.text),
                      label.text.rangeOfCharacter(from: .decimalDigits) == nil,
                      amount.x > label.x + label.width + 0.015,
                      amount.x - label.x - label.width < 0.28,
                      abs(label.y + label.height / 2 - amount.y - amount.height / 2) < max(label.height, amount.height) * 1.25 else { return false }
                // A quantity cell between the name and amount establishes a
                // table row. Leave it intact for the table detector.
                return !input.contains { cell in
                    cell != label && cell != amount && cell.x > label.x + label.width && cell.x < amount.x
                        && abs(cell.y - amount.y) < max(cell.height, amount.height)
                        && cell.text.rangeOfCharacter(from: .decimalDigits) != nil
                }
            }.sorted {
                abs($0.element.y + $0.element.height / 2 - amount.y - amount.height / 2)
                    < abs($1.element.y + $1.element.height / 2 - amount.y - amount.height / 2)
            }
            guard let label = candidates.first else { continue }
            var block = label.element
            block.text += "：" + amount.text; block.readingKind = .field
            let top = max(block.y + block.height, amount.y + amount.height)
            block.y = min(block.y, amount.y); block.height = top - block.y
            block.width = amount.x + amount.width - block.x
            block.confidence = min(block.confidence, amount.confidence)
            grouped.append(block); consumed.insert(index); consumed.insert(label.offset)
        }
        return input.enumerated().filter { !consumed.contains($0.offset) }.map(\.element) + grouped
    }

    private static func groupStackedPrices(_ input: [RecognizedLine]) -> [RecognizedLine] {
        var consumed = Set<Int>(), grouped: [RecognizedLine] = []
        for (index, amount) in input.enumerated() where amount.readingKind == nil && isAmount(amount.text)
            && amount.text.range(of: #"[¥￥$€£]|円|yen|JPY|USD"#, options: [.regularExpression, .caseInsensitive]) != nil {
            // Side-by-side table cells must be handled by the table detector.
            let bodyOnSameRow = input.contains { other in
                other != amount && !isAmount(other.text) && other.text.rangeOfCharacter(from: .alphanumerics) != nil
                    && abs((other.y + other.height / 2) - (amount.y + amount.height / 2)) < min(other.height, amount.height) * 0.5
            }
            if bodyOnSameRow { continue }
            let labels = input.enumerated().filter { i, label in
                let gap = label.y - (amount.y + amount.height)
                let overlap = min(label.x + label.width, amount.x + amount.width) - max(label.x, amount.x)
                return i != index && !consumed.contains(i) && label.readingKind == nil
                    && label.text.count <= 40 && !endsSentence(label.text) && !ReadingBlock.isListRow(label.text)
                    && label.text.rangeOfCharacter(from: .decimalDigits) == nil
                    && gap >= -min(label.height, amount.height) * 0.2 && gap < max(label.height, amount.height) * 1.4
                    && overlap > min(label.width, amount.width) * 0.5
            }.sorted { $0.element.y < $1.element.y }
            guard let label = labels.first else { continue }
            var block = label.element
            block.text += "：" + amount.text; block.readingKind = .field
            let top = max(block.y + block.height, amount.y + amount.height)
            block.y = min(block.y, amount.y); block.height = top - block.y
            block.width = max(block.x + block.width, amount.x + amount.width) - min(block.x, amount.x)
            block.x = min(block.x, amount.x)
            grouped.append(block); consumed.insert(index); consumed.insert(label.offset)
        }
        return input.enumerated().filter { !consumed.contains($0.offset) }.map(\.element) + grouped
    }

    private static func needsSpace(between left: String, and right: String) -> Bool {
        guard let a = left.unicodeScalars.last, let b = right.unicodeScalars.first else { return false }
        if "、。，．：；！？)]}）］｝」』】〉》,.;:!?".unicodeScalars.contains(b)
            || "([{（［｛「『【〈《".unicodeScalars.contains(a) { return false }
        let latin: (UnicodeScalar) -> Bool = { $0.value < 0x3000 }
        return latin(a) && latin(b)
    }
}
