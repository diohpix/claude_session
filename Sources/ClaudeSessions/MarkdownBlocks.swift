import Foundation

/// 마크다운 본문을 블록 단위 줄로 나누는 줄 기반 파서.
/// 제목, 목록(중첩 · 번호 · 체크박스), 코드 블록, 인용, 표, 구분선을 알아본다.
enum MarkdownBlocks {
    enum Alignment { case left, center, right }

    enum Block {
        case text(String)
        case heading(level: Int, String)
        /// 목록 항목. `marker` 가 비어 있으면 앞 항목에 이어지는 줄이다.
        case item(level: Int, marker: String, String)
        case quote(String)
        case code(language: String, lines: [String])
        case table(header: [String], alignments: [Alignment], rows: [[String]])
        case rule
        case blank
    }

    /// 줄바꿈이 없는 긴 줄을 강제로 끊는 길이.
    private static let hardLimit = 2_000

    /// 서식을 해석하지 않고 줄 그대로 나눈다 (내가 붙여 넣은 로그나 명령용).
    static func plain(_ text: String) -> [Block] {
        guard !text.isEmpty else { return [] }
        var result: [Block] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {
                result.append(.blank)
            } else {
                for piece in pieces(line) { result.append(.text(String(piece))) }
            }
        }
        return result
    }

    /// 너무 긴 줄을 `hardLimit` 길이로 자른다.
    private static func pieces(_ line: Substring) -> [Substring] {
        var line = line
        var result: [Substring] = []
        while line.count > hardLimit {
            result.append(line.prefix(hardLimit))
            line = line.dropFirst(hardLimit)
        }
        result.append(line)
        return result
    }

    static func blocks(_ text: String) -> [Block] {
        guard !text.isEmpty else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var out: [Block] = []
        /// 열려 있는 목록들의 들여쓰기 폭 (중첩 단계 계산용).
        var listIndents: [Int] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let (indent, body) = splitIndent(line)

            if body.isEmpty {
                if let last = out.last, !isBlank(last) { out.append(.blank) }
                i += 1
                continue
            }

            if let fence = openingFence(body) {
                let language = body.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
                var code: [Substring] = []
                i += 1
                while i < lines.count {
                    let (_, inner) = splitIndent(lines[i])
                    if isClosingFence(inner, fence: fence) { i += 1; break }
                    code.append(dropIndent(lines[i], upTo: indent))
                    i += 1
                }
                out.append(.code(language: language, lines: code.flatMap(pieces).map(String.init)))
                continue
            }

            if indent < 4, let (level, title) = heading(body) {
                listIndents = []
                out.append(.heading(level: level, String(title)))
                i += 1
                continue
            }

            if indent < 4, isRule(body) {
                listIndents = []
                out.append(.rule)
                i += 1
                continue
            }

            if body.contains("|"), i + 1 < lines.count, isTableDelimiter(lines[i + 1]) {
                let header = cells(body)
                var alignments = alignments(lines[i + 1])
                while alignments.count < header.count { alignments.append(.left) }
                alignments = Array(alignments.prefix(header.count))
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let (_, rowBody) = splitIndent(lines[i])
                    guard !rowBody.isEmpty, rowBody.contains("|") else { break }
                    var row = cells(rowBody)
                    while row.count < header.count { row.append("") }
                    rows.append(Array(row.prefix(header.count)))
                    i += 1
                }
                listIndents = []
                out.append(.table(header: header, alignments: alignments, rows: rows))
                continue
            }

            if body.first == ">" {
                var rest = body.dropFirst()
                if rest.first == " " { rest = rest.dropFirst() }
                out.append(.quote(String(rest)))
                i += 1
                continue
            }

            if let (marker, text) = listItem(body) {
                while let last = listIndents.last, last > indent { listIndents.removeLast() }
                if listIndents.last.map({ $0 < indent }) ?? true { listIndents.append(indent) }
                out.append(.item(level: listIndents.count - 1, marker: marker, String(text)))
                i += 1
                continue
            }

            if !listIndents.isEmpty, indent > 0 {
                // 목록 항목 아래에 들여 쓴 줄은 그 항목에 이어지는 내용이다.
                while listIndents.count > 1, let last = listIndents.last, last >= indent { listIndents.removeLast() }
                for piece in pieces(body) {
                    out.append(.item(level: listIndents.count - 1, marker: "", String(piece)))
                }
            } else {
                listIndents = []
                for piece in pieces(line) {
                    out.append(.text(String(piece)))
                }
            }
            i += 1
        }
        if let last = out.last, isBlank(last) { out.removeLast() }
        return out
    }

    private static func isBlank(_ content: Block) -> Bool {
        if case .blank = content { return true }
        return false
    }

    /// 앞쪽 들여쓰기 폭(탭은 4칸)과 나머지 내용.
    private static func splitIndent(_ line: Substring) -> (Int, Substring) {
        var width = 0
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == " " { width += 1 } else if line[index] == "\t" { width += 4 } else { break }
            index = line.index(after: index)
        }
        var body = line[index...]
        while let last = body.last, last == " " || last == "\t" || last == "\r" { body = body.dropLast() }
        return (width, body)
    }

    private static func dropIndent(_ line: Substring, upTo width: Int) -> Substring {
        var line = line
        var left = width
        while left > 0, line.first == " " {
            line = line.dropFirst()
            left -= 1
        }
        if line.last == "\r" { line = line.dropLast() }
        return line
    }

    private static func openingFence(_ body: Substring) -> String? {
        guard let first = body.first, first == "`" || first == "~" else { return nil }
        let count = body.prefix { $0 == first }.count
        guard count >= 3 else { return nil }
        // 여는 줄의 나머지에 백틱이 있으면 코드 블록이 아니라 인라인 코드다.
        if first == "`", body.dropFirst(count).contains("`") { return nil }
        return String(repeating: first, count: count)
    }

    private static func isClosingFence(_ body: Substring, fence: String) -> Bool {
        guard body.hasPrefix(fence), let mark = fence.first else { return false }
        return body.allSatisfy { $0 == mark }
    }

    private static func heading(_ body: Substring) -> (Int, Substring)? {
        guard body.first == "#" else { return nil }
        let level = body.prefix { $0 == "#" }.count
        var rest = body.dropFirst(level)
        guard level <= 6, rest.first == " " || rest.first == "\t" else { return nil }
        rest = rest.drop { $0 == " " || $0 == "\t" }
        // 닫는 `#` 들은 떼어 낸다.
        let withoutClosing = rest.reversed().drop { $0 == "#" }
        if withoutClosing.count < rest.count, withoutClosing.first == " " {
            rest = rest.prefix(withoutClosing.count - 1)
        }
        return rest.isEmpty ? nil : (level, rest)
    }

    private static func isRule(_ body: Substring) -> Bool {
        guard let mark = body.first, mark == "-" || mark == "*" || mark == "_" else { return false }
        var count = 0
        for ch in body {
            if ch == mark { count += 1 } else if ch != " " { return false }
        }
        return count >= 3
    }

    private static func listItem(_ body: Substring) -> (String, Substring)? {
        guard let first = body.first else { return nil }
        var marker: String
        var rest: Substring
        if first == "-" || first == "*" || first == "+" {
            marker = "•"
            rest = body.dropFirst()
        } else if first.isASCII, first.isNumber {
            let digits = body.prefix { $0.isASCII && $0.isNumber }
            rest = body.dropFirst(digits.count)
            guard digits.count <= 9, rest.first == "." || rest.first == ")" else { return nil }
            marker = "\(digits)."
            rest = rest.dropFirst()
        } else {
            return nil
        }
        guard rest.first == " " || rest.first == "\t" else { return nil }
        rest = rest.drop { $0 == " " || $0 == "\t" }
        if rest.hasPrefix("[ ] ") {
            marker = "☐"
            rest = rest.dropFirst(4)
        } else if rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") {
            marker = "☑"
            rest = rest.dropFirst(4)
        }
        return (marker, rest)
    }

    /// 표의 한 줄을 칸으로 나눈다. `\|` 와 인라인 코드 안의 `|` 는 칸 구분으로 보지 않는다.
    private static func rawCells(_ body: Substring) -> [String] {
        var result: [String] = []
        var current = ""
        var inCode = false
        var escaped = false
        for ch in body {
            if escaped {
                current.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
                current.append(ch)
            } else if ch == "`" {
                inCode.toggle()
                current.append(ch)
            } else if ch == "|", !inCode {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        result = result.map { $0.trimmingCharacters(in: .whitespaces) }
        if result.first == "" { result.removeFirst() }
        if result.last == "" { result.removeLast() }
        return result
    }

    private static func cells(_ body: Substring) -> [String] {
        rawCells(body).map { $0.replacingOccurrences(of: "\\|", with: "|") }
    }

    /// 구분 줄(`|:--|:-:|--:|`)에서 열 정렬을 읽는다.
    private static func alignments(_ line: Substring) -> [Alignment] {
        rawCells(splitIndent(line).1).map { part in
            switch (part.hasPrefix(":"), part.hasSuffix(":")) {
            case (true, true): return .center
            case (false, true): return .right
            default: return .left
            }
        }
    }

    private static func isTableDelimiter(_ line: Substring) -> Bool {
        let (_, body) = splitIndent(line)
        guard body.contains("-") else { return false }
        let parts = rawCells(body)
        return !parts.isEmpty && parts.allSatisfy { part in
            part.contains("-") && part.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }
}
