import Foundation

/// 세션을 만든 도구.
enum SessionSource: String, Hashable, CaseIterable {
    case claude
    case codex

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// 세션을 다시 여는 명령 (작업 폴더에서 실행).
    func resumeInvocation(sessionId: String) -> String {
        switch self {
        case .claude: return "claude --resume \(shellArg(sessionId))"
        case .codex: return "codex resume \(shellArg(sessionId))"
        }
    }
}

/// `~/.claude/sessions/<pid>.json` 에 기록된, 지금 실행 중인 세션.
struct LiveSession: Hashable {
    let pid: Int32
    let sessionId: String
    let cwd: String
    let name: String
    let status: String
    let kind: String
    let startedAt: Date?

    var statusLabel: String {
        switch status {
        case "busy": return "작업 중"
        case "idle": return "대기"
        case "shell": return "셸 실행 중"
        case "": return "열림"
        default: return status
        }
    }
}

/// 세션 기록 파일(jsonl) 하나의 요약.
struct SessionSummary: Identifiable, Hashable {
    /// 기록 파일 경로. 아직 기록 파일이 없는 열린 세션은 `live:<sessionId>`.
    let id: String
    var source: SessionSource = .claude
    var sessionId: String
    let fileURL: URL?
    /// 프로젝트 그룹 키. Claude는 `~/.claude/projects` 아래의 폴더 이름,
    /// Codex는 작업 폴더를 같은 규칙으로 바꾼 값이라 같은 폴더의 세션이 한 그룹으로 묶인다.
    var projectDir: String
    var cwd: String?
    var title: String?
    var firstPrompt: String?
    var gitBranch: String?
    var startedAt: Date?
    var modifiedAt: Date
    var size: Int64

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let firstPrompt, !firstPrompt.isEmpty { return firstPrompt }
        return "(제목 없음)"
    }

    var projectPath: String { cwd ?? projectDir }

    var projectName: String {
        guard let cwd else { return projectDir }
        return (cwd as NSString).lastPathComponent
    }

    var resumeCommand: String? {
        guard let cwd else { return nil }
        return "cd \(shellQuote(cwd)) && \(source.resumeInvocation(sessionId: sessionId))"
    }
}

struct ProjectGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let count: Int
    let latest: Date
}

struct ChatMessage: Identifiable, Hashable {
    enum Role { case user, assistant }
    let id: Int
    let role: Role
    var text: String
    var tools: [String]
    let timestamp: Date?
}

enum SidebarItem: Hashable {
    case all
    case live
    case source(SessionSource)
    /// 프로젝트. 도구를 고른 상태에서 들어왔으면 그 도구의 세션만 보인다.
    case project(String, SessionSource?)

    /// 지금 적용 중인 도구 필터.
    var activeSource: SessionSource? {
        switch self {
        case .source(let s): return s
        case .project(_, let s): return s
        case .all, .live: return nil
        }
    }
}

func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// 세션 ID처럼 보통은 안전한 값. 뜻밖의 문자가 있을 때만 따옴표로 감싼다.
func shellArg(_ s: String) -> String {
    let safe = !s.isEmpty && s.utf8.allSatisfy { c in
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x2D || c == 0x5F
    }
    return safe ? s : shellQuote(s)
}

/// 작업 폴더 경로를 Claude의 프로젝트 폴더 이름 규칙(영숫자가 아닌 글자는 `-`)으로 바꾼다.
func projectKey(forPath path: String) -> String {
    String(String.UnicodeScalarView(path.utf16.map { u -> Unicode.Scalar in
        let alnum = (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A)
        return alnum ? Unicode.Scalar(UInt8(u)) : "-"
    }))
}

func abbreviateHome(_ path: String) -> String {
    let home = NSHomeDirectory()
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
}
