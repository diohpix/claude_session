import AppKit

/// 마크다운 표 하나를 터미널(Claude Code CLI)처럼 그리는 첨부.
///
/// 고정폭 글꼴로 쓰고, `┌─┬─┐ │ ├─┼─┤ └─┴─┘` 자리에 테두리를 두르며 칸 양옆에 한 글자씩 여백을 둔다.
/// 한글은 고정폭 글꼴에 없어 대체 글꼴로 그려지고 폭이 영문 두 글자와 맞지 않으므로,
/// 글자 칸 수를 세지 않고 글자마다 실제 폭을 재서 놓는다. 그래서 열이 어긋나지 않고 한글 사이도 벌어지지 않는다.
///
/// 표 전체가 글자 하나 자리를 차지하고, 줄 너비가 정해지면 그 너비에 맞춰
/// 열 너비를 나누고 칸 안에서 줄바꿈한다. 복사할 때는 `markdown` 이 그 자리에 들어간다.
final class TableAttachment: NSTextAttachment {
    let markdown: String

    /// 글자 하나 (또는 하나로 보이는 글자 묶음).
    private struct Glyph {
        let text: String
        let attributes: [NSAttributedString.Key: Any]
        let width: CGFloat
        var isSpace: Bool { text == " " }
    }

    private typealias Line = [Glyph]

    private struct Layout {
        let available: CGFloat
        /// 열마다 글 자리 너비 (양옆 여백 · 테두리 제외).
        let columns: [CGFloat]
        /// 행마다, 열마다 줄바꿈된 줄들.
        let rows: [[[Line]]]
        let size: CGSize
    }

    private let cells: [[Line]]
    private let alignments: [MarkdownBlocks.Alignment]
    private let font: NSFont
    private let cellWidth: CGFloat
    private let lineHeight: CGFloat
    private let lock = NSLock()
    private var cached: Layout?

    /// 너비가 모자랄 때도 열이 이보다 좁아지지는 않는다 (글자 수).
    private static let minColumn: CGFloat = 4

    /// `header` 와 `rows` 는 서식이 입혀진 칸 글. `source` 는 복사용 원문 칸 글.
    init(
        header: [NSAttributedString], rows: [[NSAttributedString]],
        alignments: [MarkdownBlocks.Alignment], source: (header: [String], rows: [[String]])
    ) {
        let size = NSFont.systemFontSize - 1
        let regular = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: size, weight: .semibold)
        font = regular
        cellWidth = ("0" as NSString).size(withAttributes: [.font: regular]).width
        lineHeight = ceil((regular.ascender - regular.descender + regular.leading) * 1.25)
        cells = ([header] + rows).map { row in row.map { Self.glyphs($0, regular: regular, bold: bold) } }
        self.alignments = alignments
        markdown = Self.markdown(header: source.header, rows: source.rows)
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: TextKit 2

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        // 제안된 줄 너비에는 문단 들여쓰기가 빠져 있지 않다.
        var width = proposedLineFragment.width
        if let style = attributes[.paragraphStyle] as? NSParagraphStyle {
            width -= style.firstLineHeadIndent
            if style.tailIndent < 0 { width += style.tailIndent }
        }
        return CGRect(origin: .zero, size: layout(for: max(width, 1)).size)
    }

    override func image(
        for bounds: CGRect,
        attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSImage? {
        let layout = currentLayout(width: bounds.width)
        return NSImage(size: bounds.size, flipped: true) { [self] _ in
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                draw(layout)
            }
            return true
        }
    }

    /// 기본 구현은 첨부를 뷰로 띄우는 쪽을 골라서 `image(for:...)` 를 부르지 않는다.
    override func viewProvider(
        for parentView: NSView?, location: any NSTextLocation, textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        nil
    }

    // MARK: 배치

    private func currentLayout(width: CGFloat) -> Layout {
        lock.lock()
        let last = cached
        lock.unlock()
        if let last, abs(last.size.width - width) < 0.5 { return last }
        return layout(for: width)
    }

    private func layout(for available: CGFloat) -> Layout {
        lock.lock()
        if let cached, cached.available == available {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let count = alignments.count
        // 열마다 글 자리 말고도 왼쪽 테두리와 양옆 여백 한 글자씩이 붙고, 맨 오른쪽 테두리가 하나 더 있다.
        let budget = max(available - CGFloat(count * 3 + 1) * cellWidth, 0)
        let minimum = Self.minColumn * cellWidth

        var natural = [CGFloat](repeating: cellWidth, count: count)
        for row in cells {
            for (column, cell) in row.enumerated() where column < count {
                natural[column] = max(natural[column], cell.reduce(0) { $0 + $1.width })
            }
        }

        // 좁은 열부터 제 너비를 주고, 남은 칸을 나머지 열이 똑같이 나눠 갖는다.
        var columns = natural
        var remaining = budget
        var left = count
        for column in natural.indices.sorted(by: { natural[$0] < natural[$1] }) {
            let share = (remaining / CGFloat(max(left, 1))).rounded(.down)
            columns[column] = max(min(natural[column], share), min(natural[column], minimum))
            remaining -= columns[column]
            left -= 1
        }

        let rows: [[[Line]]] = cells.map { row in
            columns.indices.map { column in
                column < row.count ? Self.wrap(row[column], width: columns[column]) : [[]]
            }
        }
        let lines = 1 + rows.reduce(0) { $0 + ($1.map(\.count).max() ?? 1) + 1 }
        let width = columns.reduce(0, +) + CGFloat(count * 3 + 1) * cellWidth
        let size = CGSize(width: ceil(width), height: CGFloat(lines) * lineHeight)

        let layout = Layout(available: available, columns: columns, rows: rows, size: size)
        lock.lock()
        cached = layout
        lock.unlock()
        return layout
    }

    /// 낱말 단위로 줄바꿈하고, 한 줄에 다 들어가지 않는 낱말은 글자 단위로 끊는다.
    private static func wrap(_ glyphs: Line, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line: Line = []
        var used: CGFloat = 0
        func flush() {
            while line.last?.isSpace == true { line.removeLast() }
            lines.append(line)
            line = []
            used = 0
        }
        var i = 0
        while i < glyphs.count {
            if glyphs[i].isSpace {
                if used > 0, used + glyphs[i].width <= width {
                    line.append(glyphs[i])
                    used += glyphs[i].width
                } else if used > 0 {
                    flush()
                }
                i += 1
                continue
            }
            var end = i
            var wordWidth: CGFloat = 0
            while end < glyphs.count, !glyphs[end].isSpace {
                wordWidth += glyphs[end].width
                end += 1
            }
            if used + wordWidth > width, used > 0, wordWidth <= width { flush() }
            for glyph in glyphs[i..<end] {
                if used + glyph.width > width, used > 0 { flush() }
                line.append(glyph)
                used += glyph.width
            }
            i = end
        }
        if !line.isEmpty || lines.isEmpty { flush() }
        return lines
    }

    // MARK: 그리기

    private func draw(_ layout: Layout) {
        // 테두리 글자가 놓이는 자리의 왼쪽 끝.
        var borders: [CGFloat] = [0]
        for width in layout.columns { borders.append(borders.last! + width + cellWidth * 3) }

        func y(_ line: Int) -> CGFloat { CGFloat(line) * lineHeight }
        func center(_ value: CGFloat) -> CGFloat { value.rounded(.down) + 0.5 }

        // 테두리는 상자 그리기 글자가 놓일 칸의 한가운데를 지나는 선으로 그린다.
        // 글자로 찍으면 줄 간격 때문에 세로선이 끊어져 보인다.
        let path = NSBezierPath()
        let left = center(borders.first! + cellWidth / 2)
        let right = center(borders.last! + cellWidth / 2)
        var line = 0
        var top: CGFloat = 0
        var bottom: CGFloat = 0
        func separator() {
            let position = center(y(line) + lineHeight / 2)
            if line == 0 { top = position }
            bottom = position
            path.move(to: CGPoint(x: left, y: position))
            path.line(to: CGPoint(x: right, y: position))
            line += 1
        }

        let inset = (lineHeight - (font.ascender - font.descender)) / 2
        separator()
        for row in layout.rows {
            for (column, cellLines) in row.enumerated() {
                let width = layout.columns[column]
                for (offset, glyphs) in cellLines.enumerated() {
                    let used = glyphs.reduce(0) { $0 + $1.width }
                    var x = borders[column] + cellWidth * 2
                    switch alignments[column] {
                    case .left: break
                    case .center: x += ((width - used) / 2).rounded()
                    case .right: x += width - used
                    }
                    let origin = y(line + offset) + inset
                    for glyph in glyphs {
                        if !glyph.isSpace {
                            NSAttributedString(string: glyph.text, attributes: glyph.attributes)
                                .draw(at: CGPoint(x: x, y: origin))
                        }
                        x += glyph.width
                    }
                }
            }
            line += row.map(\.count).max() ?? 1
            separator()
        }

        for border in borders {
            let position = center(border + cellWidth / 2)
            path.move(to: CGPoint(x: position, y: top))
            path.line(to: CGPoint(x: position, y: bottom))
        }
        NSColor.tertiaryLabelColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: 도우미

    /// 서식 있는 칸 글을 고정폭 글꼴의 글자 단위로 나눈다. 굵은 글씨는 굵은 고정폭으로 바꾼다.
    private static func glyphs(_ text: NSAttributedString, regular: NSFont, bold: NSFont) -> Line {
        var result: Line = []
        let string = text.string as NSString
        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length), options: .byComposedCharacterSequences
        ) { piece, range, _, _ in
            guard var piece else { return }
            if piece == "\t" || piece == "\n" { piece = " " }
            var attributes = text.attributes(at: range.location, effectiveRange: nil)
            let isBold = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            attributes[.font] = isBold ? bold : regular
            let width = (piece as NSString).size(withAttributes: [.font: attributes[.font]!]).width
            result.append(Glyph(text: piece, attributes: attributes, width: width))
        }
        return result
    }

    private static func markdown(header: [String], rows: [[String]]) -> String {
        func line(_ cells: [String]) -> String {
            "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
        }
        return ([line(header), "|" + header.map { _ in "---|" }.joined()] + rows.map(line)).joined(separator: "\n")
    }
}
