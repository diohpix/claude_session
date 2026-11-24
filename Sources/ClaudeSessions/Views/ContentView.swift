import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var store
    @State private var filter: SidebarItem? = .all
    @State private var selection: Set<SessionSummary.ID> = []
    @State private var query = ""

    private var filtered: [SessionSummary] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return store.sessions.filter { s in
            switch filter ?? .all {
            case .all: break
            case .live: if store.live[s.sessionId] == nil { return false }
            case .source(let source): if s.source != source { return false }
            case .project(let dir, let source):
                if s.projectDir != dir { return false }
                if let source, s.source != source { return false }
            }
            guard !q.isEmpty else { return true }
            return [s.title, s.firstPrompt, s.cwd, s.sessionId, s.gitBranch, store.live[s.sessionId]?.name]
                .contains { $0?.localizedCaseInsensitiveContains(q) == true }
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $filter)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } content: {
            SessionListView(sessions: filtered, selection: $selection)
                .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 600)
                .searchable(text: $query, placement: .toolbar, prompt: "제목, 요청, 경로 검색")
        } detail: {
            if selection.count == 1, let s = store.sessions.first(where: { selection.contains($0.id) }) {
                TranscriptView(session: s)
                    .id(s.id)
            } else if selection.count > 1 {
                MultiSelectionView(sessions: store.sessions.filter { selection.contains($0.id) })
            } else {
                ContentUnavailableView(
                    "세션을 선택하세요",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("왼쪽 목록에서 세션을 고르면 대화 내용이 표시됩니다.")
                )
            }
        }
        .navigationTitle("AI Sessions")
        .confirmationDialog(
            store.pendingDelete.count == 1
                ? "이 세션을 휴지통으로 옮길까요?"
                : "\(store.pendingDelete.count)개 세션을 휴지통으로 옮길까요?",
            isPresented: Binding(get: { !store.pendingDelete.isEmpty }, set: { if !$0 { store.pendingDelete = [] } }),
            presenting: store.pendingDelete
        ) { sessions in
            Button("휴지통으로 이동", role: .destructive) {
                selection.subtract(sessions.map(\.id))
                store.delete(sessions)
            }
            Button("취소", role: .cancel) {}
        } message: { sessions in
            if sessions.count == 1, let session = sessions.first {
                Text("\(session.displayTitle)\n\(abbreviateHome(session.projectPath))\n\n휴지통에서 되돌릴 수 있습니다.")
            } else {
                let names = sessions.prefix(8).map { "• \($0.displayTitle)" }
                let more = sessions.count > 8 ? ["외 \(sessions.count - 8)개"] : []
                Text((names + more).joined(separator: "\n") + "\n\n휴지통에서 되돌릴 수 있습니다.")
            }
        }
        .alert(
            "오류",
            isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

/// 목록에서 여러 세션을 골랐을 때 상세 영역에 보이는 요약.
private struct MultiSelectionView: View {
    @Environment(SessionStore.self) private var store
    let sessions: [SessionSummary]

    var body: some View {
        let deletable = store.deletable(sessions)
        let skipped = sessions.count - deletable.count
        ContentUnavailableView {
            Label("\(sessions.count)개 세션 선택됨", systemImage: "checklist")
        } description: {
            if skipped > 0 {
                Text("실행 중이거나 기록 파일이 없는 \(skipped)개 세션은 삭제 대상에서 제외됩니다.")
            } else {
                Text("⌘-클릭 또는 ⇧-클릭으로 선택을 바꿀 수 있습니다.")
            }
        } actions: {
            Button("\(deletable.count)개 세션을 휴지통으로 이동…", systemImage: "trash", role: .destructive) {
                store.pendingDelete = deletable
            }
            .disabled(deletable.isEmpty)
        }
    }
}
