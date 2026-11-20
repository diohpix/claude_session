import Foundation

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
    let sessionId: String
    let fileURL: URL?
    /// `~/.claude/projects` 아래의 폴더 이름 (프로젝트 그룹 키).
    let projectDir: String
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
        return "cd \(shellQuote(cwd)) && claude --resume \(sessionId)"
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
    case project(String)
}

func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func abbreviateHome(_ path: String) -> String {
    let home = NSHomeDirectory()
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
}
