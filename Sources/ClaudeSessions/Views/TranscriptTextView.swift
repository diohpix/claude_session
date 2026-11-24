import AppKit
import SwiftUI

// 대화 내용 전체를 텍스트 뷰 하나에 그린다.
//
// - 마우스로 여러 줄 · 여러 메시지를 끌어서 선택하고 복사할 수 있다.
// - TextKit 2 는 화면에 보이는 문단만 배치하므로 긴 세션에서도 창 크기를 바꿀 때 버벅이지 않는다.
// - 말풍선 · 코드 블록 배경 같은 장식은 문단마다 붙인 속성을 보고 `TranscriptFragment` 가 그린다.

private extension NSAttributedString.Key {
    /// 말풍선 배경. 값은 `Bubble.rawValue`.
    static let bubble = NSAttributedString.Key("transcript.bubble")
    /// 코드 블록 · 표의 안쪽 배경. 값은 `Edge.rawValue`.
    static let panel = NSAttributedString.Key("transcript.panel")
    static let quoteBar = NSAttributedString.Key("transcript.quoteBar")
    static let rule = NSAttributedString.Key("transcript.rule")
}

/// 문단이 배경 영역의 첫 줄 / 마지막 줄인지.
private struct Edge: OptionSet {
    let rawValue: Int
    static let first = Edge(rawValue: 1)
    static let last = Edge(rawValue: 2)
    static let user = Edge(rawValue: 4)
}

private enum Metrics {
    static let inset: CGFloat = 16
    /// 내 메시지 말풍선은 왼쪽을 이만큼 비운다.
    static let userLeading: CGFloat = 60
    static let bubblePadding: CGFloat = 12
    static let panelPadding: CGFloat = 10
    static let listStep: CGFloat = 18
    static let markerWidth: CGFloat = 22
    /// 본문 줄 높이 배율. 글꼴 기본 줄 높이는 한글이 빽빽해 보여서 조금 띄운다.
    static let lineHeight: CGFloat = 1.35
    static let codeLineHeight: CGFloat = 1.2
}

/// 화면에 그릴 준비가 끝난 대화 내용.
final class TranscriptDocument: @unchecked Sendable {
    let text: NSAttributedString
    var isEmpty: Bool { text.length == 0 }

    /// 아주 긴 붙여넣기 때문에 화면이 멈추지 않도록 메시지 하나의 표시 길이를 제한한다.
    private static let displayLimit = 20_000

    init(messages: [ChatMessage], source: SessionSource, icon: NSImage?) {
        var builder = Builder(source: source, icon: icon)
        for message in messages {
            builder.append(message, limit: Self.displayLimit)
        }
        text = builder.result
    }
}

private struct Builder {
    let source: SessionSource
    let icon: NSImage?
    let result = NSMutableAttributedString()

    private let body = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    private let code = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
    private var fonts: [String: NSFont] = [:]
    private let timeFormat = Date.FormatStyle(date: .numeric, time: .shortened)

    /// 현재 메시지의 말풍선 안쪽 왼쪽 / 오른쪽 여백.
    private var leading: CGFloat = 0
    private var isUser = false
    /// 현재 메시지가 시작된 위치 (말풍선 속성을 한꺼번에 붙이려고 기억한다).
    private var paragraphs: [NSRange] = []

    init(source: SessionSource, icon: NSImage?) {
        self.source = source
        self.icon = icon
    }

    mutating func append(_ message: ChatMessage, limit: Int) {
        isUser = message.role == .user
        leading = (isUser ? Metrics.userLeading : 0) + Metrics.bubblePadding
        paragraphs = []

        if result.length > 0 {
            // 말풍선 사이 간격.
            let gap = NSMutableParagraphStyle()
            gap.minimumLineHeight = 14
            gap.maximumLineHeight = 14
            result.append(NSAttributedString(string: "\n", attributes: [.font: small, .paragraphStyle: gap]))
        }

        appendHeader(message)

        var text = message.text
        if text.count > limit {
            text = String(text.prefix(limit)) + "\n\n…(이하 생략)"
        }
        // 내가 붙여 넣은 로그나 명령은 `#`, `-` 같은 글자가 서식으로 바뀌면 안 되므로 줄 그대로 보여 준다.
        let blocks = isUser ? MarkdownBlocks.plain(text) : MarkdownBlocks.blocks(text)
        for block in blocks { append(block) }

        if !message.tools.isEmpty {
            let line = NSAttributedString(string: "도구  " + toolSummary(message.tools), attributes: [
                .font: small, .foregroundColor: NSColor.secondaryLabelColor,
            ])
            paragraph(line, style: style(before: 6))
        }

        // 말풍선 속성: 첫 문단과 마지막 문단은 모서리를 둥글리고 위아래 여백을 준다.
        for (index, range) in paragraphs.enumerated() {
            var edge: Edge = isUser ? .user : []
            if index == 0 { edge.insert(.first) }
            if index == paragraphs.count - 1 { edge.insert(.last) }
            result.addAttribute(.bubble, value: edge.rawValue, range: range)
            guard edge.contains(.first) || edge.contains(.last),
                  let old = result.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
                  let style = old.mutableCopy() as? NSMutableParagraphStyle else { continue }
            if edge.contains(.first) { style.paragraphSpacingBefore += 10 }
            if edge.contains(.last) { style.paragraphSpacing += 10 }
            result.addAttribute(.paragraphStyle, value: style, range: range)
        }
    }

    // MARK: 블록

    private mutating func appendHeader(_ message: ChatMessage) {
        let line = NSMutableAttributedString()
        if !isUser, let icon {
            let attachment = NSTextAttachment()
            attachment.image = icon
            attachment.bounds = CGRect(x: 0, y: -3, width: 14, height: 14)
            line.append(NSAttributedString(attachment: attachment))
            line.append(NSAttributedString(string: " ", attributes: [.font: small]))
        }
        line.append(NSAttributedString(string: isUser ? "나" : source.title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: isUser ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
        ]))
        if let timestamp = message.timestamp {
            line.append(NSAttributedString(string: "  " + timestamp.formatted(timeFormat), attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]))
        }
        paragraph(line, style: style(after: 6))
    }

    private mutating func append(_ block: MarkdownBlocks.Block) {
        switch block {
        case .text(let text):
            paragraph(inline(text, font: body), style: style())

        case .heading(let level, let text):
            let font: NSFont
            switch level {
            case 1: font = .systemFont(ofSize: 20, weight: .bold)
            case 2: font = .systemFont(ofSize: 17, weight: .semibold)
            case 3: font = .systemFont(ofSize: 15, weight: .semibold)
            default: font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            }
            paragraph(inline(text, font: font), style: style(before: level <= 2 ? 8 : 5, after: 4))

        case .item(let level, let marker, let text):
            let markerX = leading + CGFloat(level) * Metrics.listStep + 4
            let textX = markerX + Metrics.markerWidth - 4
            let style = style(before: 1.5, after: 1.5)
            style.headIndent = textX
            style.tabStops = [NSTextTab(textAlignment: .left, location: textX)]
            let line = NSMutableAttributedString()
            if marker.isEmpty {
                style.firstLineHeadIndent = textX
            } else {
                style.firstLineHeadIndent = markerX
                line.append(NSAttributedString(string: marker + "\t", attributes: [
                    .font: marker == "•" ? body : NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]))
            }
            line.append(inline(text, font: body))
            paragraph(line, style: style)

        case .quote(let text):
            let style = style(before: 1, after: 1)
            style.firstLineHeadIndent = leading + 12
            style.headIndent = leading + 12
            let range = paragraph(inline(text, font: body, color: .secondaryLabelColor), style: style)
            result.addAttribute(.quoteBar, value: true, range: range)

        case .code(let language, let lines):
            var rows: [NSAttributedString] = []
            if !language.isEmpty {
                rows.append(NSAttributedString(string: language, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .regular),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]))
            }
            for line in lines.isEmpty ? [""] : lines {
                rows.append(NSAttributedString(string: line, attributes: [.font: code, .foregroundColor: NSColor.labelColor]))
            }
            panel(rows, styles: rows.map { _ in
                let style = style()
                style.lineHeightMultiple = Metrics.codeLineHeight
                return style
            })

        case .table(let header, let alignments, let rows):
            let bold = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            let attachment = TableAttachment(
                header: header.map { inline($0, font: bold) },
                rows: rows.map { $0.map { inline($0, font: body) } },
                alignments: alignments,
                source: (header, rows))
            // 첨부 줄은 본문 줄 높이 배율을 쓰지 않는다 (표 높이만큼 위가 벌어진다).
            let style = style(before: 6, after: 6)
            style.lineHeightMultiple = 1
            let line = NSMutableAttributedString(attachment: attachment)
            line.addAttribute(.font, value: small, range: NSRange(location: 0, length: line.length))
            paragraph(line, style: style)

        case .rule:
            let style = style()
            style.minimumLineHeight = 17
            style.maximumLineHeight = 17
            let range = paragraph(NSAttributedString(string: " ", attributes: [.font: small]), style: style)
            result.addAttribute(.rule, value: true, range: range)

        case .blank:
            let style = style()
            style.minimumLineHeight = 8
            style.maximumLineHeight = 8
            paragraph(NSAttributedString(string: "", attributes: [.font: small]), style: style)
        }
    }

    /// 배경이 깔리는 묶음(코드 블록, 표)을 넣는다.
    private mutating func panel(_ lines: [NSAttributedString], styles: [NSMutableParagraphStyle]) {
        for (index, line) in lines.enumerated() {
            let style = styles[index]
            style.firstLineHeadIndent = leading + Metrics.panelPadding
            style.headIndent = leading + Metrics.panelPadding
            style.tailIndent = -(Metrics.bubblePadding + Metrics.panelPadding)
            var edge: Edge = []
            if index == 0 {
                edge.insert(.first)
                style.paragraphSpacingBefore += 11
            }
            if index == lines.count - 1 {
                edge.insert(.last)
                style.paragraphSpacing += 11
            }
            let range = paragraph(line, style: style)
            result.addAttribute(.panel, value: edge.rawValue, range: range)
        }
    }

    // MARK: 도우미

    private func style(before: CGFloat = 0, after: CGFloat = 0) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = leading
        style.headIndent = leading
        style.tailIndent = -Metrics.bubblePadding
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.lineBreakMode = .byWordWrapping
        style.lineHeightMultiple = Metrics.lineHeight
        return style
    }

    @discardableResult
    private mutating func paragraph(_ line: NSAttributedString, style: NSParagraphStyle) -> NSRange {
        let start = result.length
        result.append(line)
        // 문단 끝 줄바꿈은 마지막 글자의 글꼴을 따라가게 해서 줄 높이가 달라지지 않게 한다.
        var attributes: [NSAttributedString.Key: Any] = [.font: body]
        if line.length > 0, let font = line.attribute(.font, at: line.length - 1, effectiveRange: nil) {
            attributes[.font] = font
        }
        result.append(NSAttributedString(string: "\n", attributes: attributes))
        let range = NSRange(location: start, length: result.length - start)
        result.addAttribute(.paragraphStyle, value: style, range: range)
        paragraphs.append(range)
        return range
    }

    /// 줄 안의 서식(굵게, 기울임, 취소선, 인라인 코드, 링크)을 해석한다.
    private mutating func inline(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSAttributedString {
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        // 서식 글자가 없는 줄은 해석을 건너뛴다 (대부분의 줄이 여기에 해당한다).
        guard text.utf8.contains(where: { byte in
            byte == UInt8(ascii: "*") || byte == UInt8(ascii: "_") || byte == UInt8(ascii: "`")
                || byte == UInt8(ascii: "[") || byte == UInt8(ascii: "~") || byte == UInt8(ascii: "\\")
                || byte == UInt8(ascii: "<") || byte == UInt8(ascii: "&")
        }) else {
            return NSAttributedString(string: text, attributes: plain)
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: plain)
        }
        let line = NSMutableAttributedString()
        for run in parsed.runs {
            var attributes = plain
            if let intent = run.inlinePresentationIntent {
                let bold = intent.contains(.stronglyEmphasized)
                let italic = intent.contains(.emphasized)
                if intent.contains(.code) {
                    attributes[.font] = variant(of: font, bold: bold, italic: false, mono: true)
                    attributes[.backgroundColor] = NSColor.labelColor.withAlphaComponent(0.08)
                } else if bold || italic {
                    attributes[.font] = variant(of: font, bold: bold, italic: italic, mono: false)
                }
                if intent.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            if let link = run.link {
                attributes[.link] = link
            }
            line.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return line
    }

    private mutating func variant(of font: NSFont, bold: Bool, italic: Bool, mono: Bool) -> NSFont {
        let key = "\(font.fontName)-\(font.pointSize)-\(bold)-\(italic)-\(mono)"
        if let cached = fonts[key] { return cached }
        var made: NSFont
        if mono {
            made = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: bold ? .semibold : .regular)
        } else {
            var traits = font.fontDescriptor.symbolicTraits
            if bold { traits.insert(.bold) }
            if italic { traits.insert(.italic) }
            made = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
        }
        fonts[key] = made
        return made
    }

    private func toolSummary(_ tools: [String]) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for tool in tools {
            if counts[tool] == nil { order.append(tool) }
            counts[tool, default: 0] += 1
        }
        return order.map { counts[$0]! > 1 ? "\($0) ×\(counts[$0]!)" : $0 }.joined(separator: ", ")
    }
}

// MARK: - 뷰

struct TranscriptTextView: NSViewRepresentable {
    let document: TranscriptDocument

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = TranscriptNSTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: Metrics.inset, height: Metrics.inset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textLayoutManager?.delegate = context.coordinator
        scrollView.documentView = textView

        context.coordinator.attach(scrollView: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.show(document)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextLayoutManagerDelegate {
        private weak var scrollView: NSScrollView?
        private weak var textView: NSTextView?
        private var shown: TranscriptDocument?
        /// 맨 아래를 보고 있는지. 그렇다면 내용이 늘거나 창 크기가 바뀌어도 맨 아래에 붙여 둔다.
        private var pinnedToBottom = true
        private var isAdjusting = false

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(didScroll), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            NotificationCenter.default.addObserver(
                self, selector: #selector(didResize), name: NSView.frameDidChangeNotification, object: scrollView)
        }

        func show(_ document: TranscriptDocument) {
            guard document !== shown, let textView, let storage = textView.textStorage else { return }
            let isFirst = shown == nil
            shown = document
            let new = document.text
            if isFirst {
                storage.setAttributedString(new)
            } else {
                // 진행 중인 세션: 달라진 뒷부분만 바꿔서 선택 영역과 스크롤 위치를 지킨다.
                // 문단 속성(말풍선 끝 모양)이 함께 바뀌므로 달라지기 시작한 문단의 처음부터 바꾼다.
                let old = storage.string as NSString
                let same = (old.commonPrefix(with: new.string, options: .literal) as NSString).length
                let start = old.paragraphRange(for: NSRange(location: max(min(same, old.length) - 1, 0), length: 0)).location
                storage.replaceCharacters(
                    in: NSRange(location: start, length: old.length - start),
                    with: new.attributedSubstring(from: NSRange(location: start, length: new.length - start)))
            }
            if pinnedToBottom { scrollToBottom() }
        }

        private func scrollToBottom() {
            guard let textView else { return }
            isAdjusting = true
            textView.scrollToEndOfDocument(nil)
            isAdjusting = false
            // TextKit 2 는 보이지 않는 부분의 높이를 어림하므로, 배치가 끝난 뒤 한 번 더 맞춘다.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pinnedToBottom, let textView = self.textView else { return }
                self.isAdjusting = true
                textView.scrollToEndOfDocument(nil)
                self.isAdjusting = false
            }
        }

        @objc private func didScroll() {
            guard !isAdjusting, let scrollView, let textView, !scrollView.inLiveResize else { return }
            let visible = scrollView.contentView.bounds
            pinnedToBottom = visible.maxY >= textView.frame.height - 24
        }

        @objc private func didResize() {
            guard pinnedToBottom, let textView else { return }
            isAdjusting = true
            textView.scrollToEndOfDocument(nil)
            isAdjusting = false
        }

        nonisolated func textLayoutManager(
            _ textLayoutManager: NSTextLayoutManager,
            textLayoutFragmentFor location: any NSTextLocation,
            in textElement: NSTextElement
        ) -> NSTextLayoutFragment {
            guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else {
                return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
            }
            let attributes = paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
            guard let bubble = attributes[.bubble] as? Int else {
                return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
            }
            let fragment = TranscriptFragment(textElement: textElement, range: textElement.elementRange)
            fragment.bubble = Edge(rawValue: bubble)
            fragment.panel = (attributes[.panel] as? Int).map(Edge.init(rawValue:))
            fragment.hasQuoteBar = attributes[.quoteBar] != nil
            fragment.isRule = attributes[.rule] != nil
            if let style = attributes[.paragraphStyle] as? NSParagraphStyle {
                fragment.headIndent = style.headIndent
                fragment.spacingBefore = style.paragraphSpacingBefore
                fragment.spacingAfter = style.paragraphSpacing
            }
            return fragment
        }
    }
}

private final class TranscriptNSTextView: NSTextView {
    // 말풍선 · 코드 블록 배경은 글의 줄바꿈이 그대로여도 너비에 따라 달라진다.
    // 창 크기를 끄는 동안 AppKit 은 새로 드러난 부분만 다시 그리므로, 너비가 바뀌면 전체를 다시 그리게 한다.
    override var preservesContentDuringLiveResize: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { needsDisplay = true }
    }

    /// 복사할 때 서식과 아이콘 자리 글자를 빼고 글만 넘긴다.
    override func copy(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let text = selectedRanges
            .map { range -> String in
                // 표 첨부 자리에는 마크다운 표 원문을 넣는다.
                let part = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range.rangeValue))
                part.enumerateAttribute(.attachment, in: NSRange(location: 0, length: part.length), options: .reverse) { value, range, _ in
                    if let table = value as? TableAttachment {
                        part.replaceCharacters(in: range, with: table.markdown)
                    }
                }
                return part.string
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\u{FFFC} ", with: "")
            .replacingOccurrences(of: "\u{FFFC}", with: "")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// 문단 하나를 그리면서 말풍선 · 코드 블록 배경, 인용 막대, 구분선을 함께 그린다.
private final class TranscriptFragment: NSTextLayoutFragment {
    var bubble: Edge = []
    var panel: Edge?
    var hasQuoteBar = false
    var isRule = false
    var headIndent: CGFloat = 0
    var spacingBefore: CGFloat = 0
    var spacingAfter: CGFloat = 0

    private var containerWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.maxX
    }

    override var renderingSurfaceBounds: CGRect {
        let frame = layoutFragmentFrame
        let full = CGRect(x: -frame.minX, y: 0, width: containerWidth, height: frame.height)
        return super.renderingSurfaceBounds.union(full)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let frame = layoutFragmentFrame
        // 문단 영역 전체 (컨테이너 왼쪽 끝부터 오른쪽 끝까지).
        let left = point.x - frame.minX
        let isUser = bubble.contains(.user)
        let bubbleRect = CGRect(
            x: left + (isUser ? Metrics.userLeading : 0), y: point.y,
            width: containerWidth - (isUser ? Metrics.userLeading : 0), height: frame.height)

        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            context.saveGState()
            let bubbleColor = isUser
                ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                : NSColor.controlBackgroundColor
            context.setFillColor(bubbleColor.cgColor)
            fill(bubbleRect, radius: 10, top: bubble.contains(.first), bottom: bubble.contains(.last), in: context)

            if let panel {
                // 묶음 바깥 여백(첫 줄 위, 마지막 줄 아래 4pt)은 말풍선 색으로 남긴다.
                var rect = bubbleRect.insetBy(dx: Metrics.bubblePadding, dy: 0)
                if panel.contains(.first) {
                    rect.origin.y += 4
                    rect.size.height -= 4
                }
                if panel.contains(.last) { rect.size.height -= 4 }
                context.setFillColor(NSColor.labelColor.withAlphaComponent(0.06).cgColor)
                fill(rect, radius: 6, top: panel.contains(.first), bottom: panel.contains(.last), in: context)
            }
            if hasQuoteBar {
                context.setFillColor(NSColor.tertiaryLabelColor.cgColor)
                context.fill(CGRect(x: left + headIndent - 12, y: point.y, width: 3, height: frame.height))
            }
            if isRule {
                context.setFillColor(NSColor.separatorColor.cgColor)
                context.fill(CGRect(
                    x: bubbleRect.minX + Metrics.bubblePadding, y: (point.y + frame.height / 2).rounded(),
                    width: bubbleRect.width - Metrics.bubblePadding * 2, height: 1))
            }
            context.restoreGState()
        }
        super.draw(at: point, in: context)
    }

    /// 위 / 아래 모서리만 골라서 둥글린 사각형을 채운다.
    private func fill(_ rect: CGRect, radius: CGFloat, top: Bool, bottom: Bool, in context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        let r = min(radius, rect.height / 2, rect.width / 2)
        let path = CGMutablePath()
        // 뒤집힌 좌표계: minY 가 위쪽.
        path.move(to: CGPoint(x: rect.minX + (top ? r : 0), y: rect.minY))
        if top {
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        if bottom {
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        if top {
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
    }
}
