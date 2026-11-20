import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var store
    @State private var filter: SidebarItem? = .all
    @State private var selection: SessionSummary.ID?
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
            if let s = store.sessions.first(where: { $0.id == selection }) {
                TranscriptView(session: s)
                    .id(s.id)
            } else {
                ContentUnavailableView(
                    "세션을 선택하세요",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("왼쪽 목록에서 세션을 고르면 대화 내용이 표시됩니다.")
                )
            }
        }
        .navigationTitle("Claude 세션")
        .confirmationDialog(
            "이 세션을 휴지통으로 옮길까요?",
            isPresented: Binding(get: { store.pendingDelete != nil }, set: { if !$0 { store.pendingDelete = nil } }),
            presenting: store.pendingDelete
        ) { session in
            Button("휴지통으로 이동", role: .destructive) {
                if selection == session.id { selection = nil }
                store.delete(session)
            }
            Button("취소", role: .cancel) {}
        } message: { session in
            Text("\(session.displayTitle)\n\(abbreviateHome(session.projectPath))\n\n휴지통에서 되돌릴 수 있습니다.")
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
