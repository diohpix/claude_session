import SwiftUI

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--dump") {
            dump()
            return
        }
        if CommandLine.arguments.contains("--notify-check") {
            Notifier.shared.check()
            return
        }
        ClaudeSessionsApp.main()
    }

    /// 화면 없이 스캔 결과만 출력한다 (점검용).
    private static func dump() {
        let summaries = Scanner.scanAll(cache: [:])
        let live = Scanner.liveSessions()
        let merged = Scanner.merge(summaries, live: live)
        let projects = Set(merged.map(\.projectDir))
        let codex = merged.filter { $0.source == .codex }
        print("프로젝트 \(projects.count) / 세션 \(merged.count) (Claude \(merged.count - codex.count), Codex \(codex.count)) / 열린 세션 \(live.count)")
        for s in merged.prefix(15) {
            let mark = live[s.sessionId].map { "[\($0.name) \($0.status)]" } ?? ""
            print("- \(s.modifiedAt.formatted(date: .numeric, time: .shortened))  [\(s.source.title)] \(s.projectName)  \(mark) \(s.displayTitle.prefix(60))")
        }
        if let first = merged.first(where: { $0.fileURL != nil }) {
            let msgs = first.loadMessages()
            print("첫 세션 대화 메시지 수: \(msgs.count)")
        }
        if let first = codex.first, first.fileURL != nil {
            let msgs = first.loadMessages()
            let tools = msgs.reduce(0) { $0 + $1.tools.count }
            print("최근 Codex 세션: 프로젝트 \(first.projectName) / 브랜치 \(first.gitBranch ?? "-") / 제목 \(first.title == nil ? "없음" : "있음") / 메시지 \(msgs.count) / 도구 호출 \(tools)")
            print("  \(first.resumeCommand ?? "(이어 열기 불가)")")
        }
    }
}

struct ClaudeSessionsApp: App {
    @State private var store = SessionStore()

    var body: some Scene {
        WindowGroup("AI Sessions") {
            ContentView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 480)
                .task { store.start() }
        }
        .defaultSize(width: 1280, height: 780)

        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("terminal") private var terminal = TerminalApp.defaultApp.rawValue
    @AppStorage(Notifier.enabledKey) private var notifyOnIdle = true

    var body: some View {
        Form {
            Toggle("Claude 세션이 작업을 마치고 대기로 바뀌면 알림", isOn: $notifyOnIdle)
            Picker("이어 열 때 사용할 터미널", selection: $terminal) {
                ForEach(TerminalApp.allCases) { app in
                    Text(app.title).tag(app.rawValue)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
