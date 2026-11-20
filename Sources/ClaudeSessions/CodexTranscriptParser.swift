import Foundation

/// Codex CLI의 세션 기록(`~/.codex/sessions/.../rollout-*.jsonl`)을 읽는다.
/// 줄마다 `{"timestamp":…,"type":…,"payload":{…}}` 꼴이고, 대화는 `response_item` 줄에 있다.
enum CodexTranscriptParser {
    private static let mMeta = Array("\"type\":\"session_meta\"".utf8)
    private static let mItem = Array("\"type\":\"response_item\"".utf8)
    private static let mUserRole = Array("\"role\":\"user\"".utf8)
    private static let mMessage = Array("\"type\":\"message\"".utf8)
    /// `function_call`, `custom_tool_call` 등. 결과 줄(`…_call_output`)은 걸리지 않는다.
    private static let mCall = Array("_call\"".utf8)

    // MARK: - 요약

    static func summary(url: URL, modifiedAt: Date, size: Int64) -> SessionSummary {
        // 파일 이름은 `rollout-<날짜>T<시각>-<세션 UUID>.jsonl`.
        let stem = url.deletingPathExtension().lastPathComponent
        var s = SessionSummary(
            id: url.path,
            source: .codex,
            sessionId: String(stem.suffix(36)),
            fileURL: url,
            projectDir: "(알 수 없음)",
            modifiedAt: modifiedAt,
            size: size
        )
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return s }

        let iso = TranscriptParser.makeISOFormatter()
        var needMeta = true
        var needPrompt = true

        TranscriptParser.forEachLine(in: data) { line in
            guard needMeta || needPrompt else { return }
            if needMeta, TranscriptParser.contains(line, mMeta),
               let obj = TranscriptParser.decode(line), obj["type"] as? String == "session_meta",
               let p = obj["payload"] as? [String: Any] {
                needMeta = false
                if let id = p["id"] as? String, !id.isEmpty { s.sessionId = id }
                if let cwd = p["cwd"] as? String, !cwd.isEmpty {
                    s.cwd = cwd
                    s.projectDir = projectKey(forPath: cwd)
                }
                if let b = (p["git"] as? [String: Any])?["branch"] as? String, !b.isEmpty { s.gitBranch = b }
                let t = p["timestamp"] as? String ?? obj["timestamp"] as? String
                s.startedAt = t.flatMap { iso.date(from: $0) }
            } else if needPrompt, TranscriptParser.contains(line, mItem), TranscriptParser.contains(line, mUserRole),
                      let obj = TranscriptParser.decode(line), let text = userText(obj) {
                s.firstPrompt = TranscriptParser.oneLine(text, limit: 300)
                needPrompt = false
            }
        }
        return s
    }

    // MARK: - 전체 대화

    static func messages(url: URL) -> [ChatMessage] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        let iso = TranscriptParser.makeISOFormatter()
        var out: [ChatMessage] = []

        TranscriptParser.forEachLine(in: data) { line in
            guard TranscriptParser.contains(line, mItem),
                  TranscriptParser.contains(line, mMessage) || TranscriptParser.contains(line, mCall),
                  let obj = TranscriptParser.decode(line), obj["type"] as? String == "response_item",
                  let p = obj["payload"] as? [String: Any], let kind = p["type"] as? String else { return }
            let ts = (obj["timestamp"] as? String).flatMap { iso.date(from: $0) }

            var text = ""
            var tools: [String] = []
            if kind == "message" {
                switch p["role"] as? String {
                case "user":
                    guard let t = userText(obj) else { return }
                    out.append(ChatMessage(id: out.count, role: .user, text: t, tools: [], timestamp: ts))
                    return
                case "assistant":
                    text = blockTexts(p).joined(separator: "\n\n")
                default:
                    return  // developer 등 하네스가 넣은 메시지
                }
            } else if kind.hasSuffix("_call") {
                tools = [p["name"] as? String ?? String(kind.dropLast("_call".count))]
            } else {
                return
            }
            guard !text.isEmpty || !tools.isEmpty else { return }
            // 한 턴의 중간 설명·도구 호출·최종 답이 따로 기록되므로 연속된 응답은 하나로 합친다.
            if let last = out.last, last.role == .assistant {
                var merged = last
                if !text.isEmpty { merged.text += merged.text.isEmpty ? text : "\n\n" + text }
                merged.tools += tools
                out[out.count - 1] = merged
            } else {
                out.append(ChatMessage(id: out.count, role: .assistant, text: text, tools: tools, timestamp: ts))
            }
        }
        return out
    }

    // MARK: - 메시지 내용

    private static func blockTexts(_ payload: [String: Any]) -> [String] {
        guard let blocks = payload["content"] as? [[String: Any]] else { return [] }
        return blocks.compactMap { b in
            guard let t = (b["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty
            else { return nil }
            return t
        }
    }

    /// 사용자가 직접 쓴 텍스트. 사용자 메시지가 아니거나 하네스가 끼워 넣은 내용뿐이면 nil.
    private static func userText(_ obj: [String: Any]) -> String? {
        guard obj["type"] as? String == "response_item",
              let p = obj["payload"] as? [String: Any],
              p["type"] as? String == "message", p["role"] as? String == "user" else { return nil }
        let texts = blockTexts(p).filter { !isNoise($0) }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    private static func isNoise(_ text: String) -> Bool {
        for prefix in ["<environment_context>", "<user_instructions>", "<turn_aborted>"] {
            if text.hasPrefix(prefix) { return true }
        }
        return false
    }
}

extension SessionSource {
    func messages(url: URL) -> [ChatMessage] {
        switch self {
        case .claude: return TranscriptParser.messages(url: url)
        case .codex: return CodexTranscriptParser.messages(url: url)
        }
    }
}

extension SessionSummary {
    func loadMessages() -> [ChatMessage] {
        fileURL.map { source.messages(url: $0) } ?? []
    }
}
