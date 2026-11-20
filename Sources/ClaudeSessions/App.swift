import SwiftUI

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--dump") {
            dump()
            return
        }
        ClaudeSessionsApp.main()
    }

    /// 화면 없이 스캔 결과만 출력한다 (점검용).
    private static func dump() {
        let summaries = Scanner.scanProjects(cache: [:])
        let live = Scanner.liveSessions()
        let merged = Scanner.merge(summaries, live: live)
        let projects = Set(merged.map(\.projectDir))
        print("프로젝트 \(projects.count) / 세션 \(merged.count) / 열린 세션 \(live.count)")
        for s in merged.prefix(15) {
            let mark = live[s.sessionId].map { "[\($0.name) \($0.status)]" } ?? ""
            print("- \(s.modifiedAt.formatted(date: .numeric, time: .shortened))  \(s.projectName)  \(mark) \(s.displayTitle.prefix(60))")
        }
        if let first = merged.first(where: { $0.fileURL != nil }), let url = first.fileURL {
            let msgs = TranscriptParser.messages(url: url)
            print("첫 세션 대화 메시지 수: \(msgs.count)")
        }
    }
}

struct ClaudeSessionsApp: App {
    @State private var store = SessionStore()

    var body: some Scene {
        WindowGroup("Claude 세션") {
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

    var body: some View {
        Form {
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
