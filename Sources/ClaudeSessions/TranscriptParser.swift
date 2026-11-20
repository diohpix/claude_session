import Foundation

/// 세션 기록(jsonl)을 읽는다. 파일이 수십 MB일 수 있어 mmap 후 줄 단위로 훑고,
/// 필요한 타입의 줄만 JSON으로 디코딩한다.
enum TranscriptParser {
    private static let mUser = Array("\"type\":\"user\"".utf8)
    private static let mAssistant = Array("\"type\":\"assistant\"".utf8)
    private static let mAITitle = Array("\"type\":\"ai-title\"".utf8)
    private static let mCustomTitle = Array("\"type\":\"custom-title\"".utf8)
    private static let mSummary = Array("\"type\":\"summary\"".utf8)

    // MARK: - 요약

    static func summary(url: URL, projectDir: String, modifiedAt: Date, size: Int64) -> SessionSummary {
        var s = SessionSummary(
            id: url.path,
            sessionId: url.deletingPathExtension().lastPathComponent,
            fileURL: url,
            projectDir: projectDir,
            modifiedAt: modifiedAt,
            size: size
        )
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return s }

        let iso = makeISOFormatter()
        var aiTitle: String?
        var customTitle: String?
        var legacySummary: String?
        var needPrompt = true

        forEachLine(in: data) { line in
            if needPrompt, contains(line, mUser), let obj = decode(line), obj["type"] as? String == "user" {
                if s.cwd == nil { s.cwd = obj["cwd"] as? String }
                if s.gitBranch == nil, let b = obj["gitBranch"] as? String, !b.isEmpty { s.gitBranch = b }
                if s.startedAt == nil, let t = obj["timestamp"] as? String { s.startedAt = iso.date(from: t) }
                if isRealUserTurn(obj), let text = userText(obj), !isNoise(text) {
                    s.firstPrompt = oneLine(text, limit: 300)
                    needPrompt = false
                }
            } else if contains(line, mAITitle), let obj = decode(line), obj["type"] as? String == "ai-title" {
                aiTitle = obj["aiTitle"] as? String ?? aiTitle
            } else if contains(line, mCustomTitle), let obj = decode(line), obj["type"] as? String == "custom-title" {
                customTitle = obj["customTitle"] as? String ?? customTitle
            } else if contains(line, mSummary), let obj = decode(line), obj["type"] as? String == "summary" {
                legacySummary = obj["summary"] as? String ?? legacySummary
            }
        }
        s.title = customTitle ?? aiTitle ?? legacySummary
        return s
    }

    // MARK: - 전체 대화

    static func messages(url: URL) -> [ChatMessage] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        let iso = makeISOFormatter()
        var out: [ChatMessage] = []

        forEachLine(in: data) { line in
            let isUser = contains(line, mUser)
            guard isUser || contains(line, mAssistant), let obj = decode(line) else { return }
            let ts = (obj["timestamp"] as? String).flatMap { iso.date(from: $0) }

            switch obj["type"] as? String {
            case "user":
                guard isRealUserTurn(obj), let text = userText(obj), !isNoise(text) else { return }
                out.append(ChatMessage(id: out.count, role: .user, text: text, tools: [], timestamp: ts))
            case "assistant":
                guard obj["isSidechain"] as? Bool != true,
                      let msg = obj["message"] as? [String: Any],
                      let blocks = msg["content"] as? [[String: Any]] else { return }
                var text = ""
                var tools: [String] = []
                for b in blocks {
                    switch b["type"] as? String {
                    case "text":
                        if let t = b["text"] as? String, !t.isEmpty {
                            text += text.isEmpty ? t : "\n\n" + t
                        }
                    case "tool_use":
                        if let n = b["name"] as? String { tools.append(n) }
                    default:
                        break
                    }
                }
                guard !text.isEmpty || !tools.isEmpty else { return }
                // 한 턴이 여러 줄로 나뉘어 기록되므로 연속된 응답은 하나로 합친다.
                if let last = out.last, last.role == .assistant {
                    var merged = last
                    if !text.isEmpty { merged.text += merged.text.isEmpty ? text : "\n\n" + text }
                    merged.tools += tools
                    out[out.count - 1] = merged
                } else {
                    out.append(ChatMessage(id: out.count, role: .assistant, text: text, tools: tools, timestamp: ts))
                }
            default:
                return
            }
        }
        return out
    }

    // MARK: - 줄 처리

    private static func forEachLine(in data: Data, _ body: (UnsafeRawBufferPointer) -> Void) {
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            guard let base = buf.baseAddress else { return }
            let total = buf.count
            var offset = 0
            while offset < total {
                let start = base + offset
                let remaining = total - offset
                let length: Int
                if let nl = memchr(start, 0x0A, remaining) {
                    length = start.distance(to: UnsafeRawPointer(nl))
                } else {
                    length = remaining
                }
                if length > 0 {
                    body(UnsafeRawBufferPointer(start: start, count: length))
                }
                offset += length + 1
            }
        }
    }

    private static func contains(_ line: UnsafeRawBufferPointer, _ marker: [UInt8]) -> Bool {
        marker.withUnsafeBytes { m in
            memmem(line.baseAddress, line.count, m.baseAddress, m.count) != nil
        }
    }

    private static func decode(_ line: UnsafeRawBufferPointer) -> [String: Any]? {
        guard let base = line.baseAddress else { return nil }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: line.count, deallocator: .none)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - 사용자 메시지 판별

    private static func isRealUserTurn(_ obj: [String: Any]) -> Bool {
        obj["isMeta"] as? Bool != true && obj["isSidechain"] as? Bool != true
    }

    /// 사용자가 직접 쓴 텍스트. 도구 결과만 담긴 줄은 nil.
    private static func userText(_ obj: [String: Any]) -> String? {
        guard let msg = obj["message"] as? [String: Any] else { return nil }
        if let s = msg["content"] as? String {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let blocks = msg["content"] as? [[String: Any]] {
            let texts = blocks.compactMap { b -> String? in
                guard b["type"] as? String == "text" else { return nil }
                return b["text"] as? String
            }
            let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    /// 슬래시 명령 출력 등 하네스가 끼워 넣은 줄.
    private static func isNoise(_ text: String) -> Bool {
        if text.isEmpty { return true }
        for prefix in ["<local-command", "<command-", "<system-reminder>", "<task-notification>", "<bash-", "Caveat:"] {
            if text.hasPrefix(prefix) { return true }
        }
        return false
    }

    private static func oneLine(_ text: String, limit: Int) -> String {
        let collapsed = text.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
}
