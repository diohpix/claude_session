import SwiftUI

struct SessionListView: View {
    @Environment(SessionStore.self) private var store
    let sessions: [SessionSummary]
    @Binding var selection: SessionSummary.ID?

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView("세션을 읽는 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.isEmpty {
                ContentUnavailableView("세션이 없습니다", systemImage: "magnifyingglass")
            } else {
                List(sessions, selection: $selection) { session in
                    SessionRow(session: session, live: store.live[session.sessionId])
                        .contextMenu { SessionActions(session: session, live: store.live[session.sessionId]) }
                }
                .listStyle(.inset)
            }
        }
        .navigationSubtitle("\(sessions.count)개 세션")
    }
}

private struct SessionRow: View {
    let session: SessionSummary
    let live: LiveSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let live {
                    StatusBadge(live: live)
                }
                Text(session.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
            }
            if session.title != nil, let prompt = session.firstPrompt {
                Text(prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Label(session.projectName, systemImage: "folder")
                    .lineLimit(1)
                if let branch = session.gitBranch {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(session.modifiedAt.formatted(.relative(presentation: .named)))
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

struct StatusBadge: View {
    let live: LiveSession

    private var color: Color {
        switch live.status {
        case "busy": return .orange
        case "shell": return .blue
        default: return .green
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(live.statusLabel)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15), in: Capsule())
        .help("PID \(live.pid) · \(live.name)")
    }
}

/// 목록의 컨텍스트 메뉴와 상세 화면이 함께 쓰는 동작들.
struct SessionActions: View {
    @Environment(SessionStore.self) private var store
    let session: SessionSummary
    let live: LiveSession?
    @AppStorage("terminal") private var terminal = TerminalApp.defaultApp.rawValue

    private var isLive: Bool { live != nil }

    var body: some View {
        if let live {
            Button("터미널로 이동", systemImage: "terminal") {
                do {
                    try TerminalLauncher.focusTerminal(of: live.pid)
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
            .help("이 세션이 열려 있는 터미널 앱을 앞으로 가져옵니다")
        } else {
            Button("터미널에서 이어 열기", systemImage: "terminal") {
                do {
                    try TerminalLauncher.resume(session, in: TerminalApp(rawValue: terminal) ?? .defaultApp)
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
            .disabled(session.cwd == nil || session.fileURL == nil)
            .help("새 터미널 창에서 이 세션을 다시 엽니다")
        }

        Button("이어 열기 명령 복사", systemImage: "doc.on.doc") {
            if let cmd = session.resumeCommand { TerminalLauncher.copyToClipboard(cmd) }
        }
        .disabled(session.resumeCommand == nil)

        Button("Finder에서 폴더 열기", systemImage: "folder") {
            if let cwd = session.cwd { TerminalLauncher.revealInFinder(cwd) }
        }
        .disabled(session.cwd == nil)

        Divider()

        Button("휴지통으로 이동…", systemImage: "trash", role: .destructive) {
            store.pendingDelete = session
        }
        .disabled(isLive || session.fileURL == nil)
        .help(isLive ? "실행 중인 세션은 삭제할 수 없습니다" : "세션 기록을 휴지통으로 옮깁니다")
    }
}
